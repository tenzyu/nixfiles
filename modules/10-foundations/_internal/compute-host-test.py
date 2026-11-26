import json
import shlex

vm = spec["vm"]
metadata = spec["metadata"]
image = spec["image"]
vm_flag = spec["vmFlag"]

def agent(command):
    if command.startswith("incus exec lab:"):
        command = command.replace(" -- ", " --mode=non-interactive --cwd / --env PATH=/run/wrappers/bin:/run/current-system/sw/bin -- ", 1)
    return "su - agent -c " + shlex.quote(command) + " </dev/null"

def guest_ready(name):
    try:
        machine.wait_until_succeeds("timeout -k 5s 30s " + agent("incus exec lab:" + name + " -- /run/current-system/sw/bin/systemctl is-active fixture-http"), timeout=900 if vm else 300)
    except Exception:
        # A present /dev/kvm is not evidence that an inner guest booted.
        # Collect firmware/kernel/agent console before fixture cleanup.
        print(machine.execute("timeout -k 5s 20s incus info " + name + " --project lab --show-log 2>&1; timeout -k 5s 20s incus console " + name + " --project lab --show-log 2>&1; free -m; cat /proc/pressure/{cpu,memory,io}; journalctl -k --no-pager | tail -100; ps -eLo pid,tid,stat,pcpu,wchan:32,comm | grep -E 'qemu|incus'")[1])
        for command in [
            "incus exec " + name + " --project lab --mode=non-interactive --cwd / -- /run/current-system/sw/bin/true",
            "incus exec " + name + " --project lab --mode=non-interactive --cwd / -- /run/current-system/sw/bin/systemctl status fixture-http incus-agent --no-pager",
            "incus exec " + name + " --project lab --mode=non-interactive --cwd / -- /run/current-system/sw/bin/journalctl -b -u fixture-http -u incus-agent --no-pager -n 100",
        ]:
            status, output = machine.execute("timeout -k 5s 20s " + command + " </dev/null 2>&1", timeout=30)
            print(f"diagnostic: {command} (exit {status})\n{output}")
        raise

machine.start()
machine.wait_for_unit("register-nix-paths.service")
machine.wait_for_unit("incus-preseed.service")
if vm:
    machine.succeed("test -c /dev/kvm; test -r /dev/kvm; test -w /dev/kvm")
machine.wait_for_unit("incumbent.service")
incumbent = machine.succeed("systemctl show -p MainPID --value incumbent.service").strip()
machine.succeed("incus version")
def assert_unpartitioned():
    project = json.loads(machine.succeed("incus query /1.0/projects/lab"))
    profile = json.loads(machine.succeed("incus query '/1.0/profiles/default?project=lab'"))
    assert not any(k.startswith("limits.") for k in project["config"]), project
    assert not any(k.startswith("limits.") for k in profile["config"]), profile
assert_unpartitioned()
# Reproduce the old main preseed, then reapply the current native preseed.
machine.succeed("incus profile set default limits.cpu=2 limits.memory=2GiB --project lab")
machine.succeed("incus project set lab limits.instances=8 limits.virtual-machines=0 limits.cpu=8 limits.memory=8GiB")
machine.succeed("incus project get lab limits.instances | grep -Fx 8")
machine.succeed("systemctl restart incus-preseed.service")
assert_unpartitioned()
machine.succeed("incus project get lab restricted | grep -x true")
machine.succeed("incus project get lab restricted.devices.disk | grep -x managed")
machine.succeed("incus network show incuslab0")
machine.succeed("ss -ltn | grep -F '127.0.0.1:8443'")
machine.succeed("curl -fkLs https://127.0.0.1:8443/ui/ | grep -i incus")
machine.fail(agent("test -w /var/lib/incus/unix.socket"))
machine.fail(agent("test -w /var/lib/incus/unix.socket.user"))

# Enrollment is an explicit operator action. CI uses disposable credentials.
machine.succeed(agent("incus remote get-client-certificate > /home/agent/client.pem"))
machine.succeed("incus config trust add-certificate /home/agent/client.pem --projects lab --restricted")
machine.succeed(agent("incus remote add lab https://127.0.0.1:8443 --accept-certificate --project lab"))
machine.succeed(agent("incus list lab:"))
machine.fail(agent("incus project set lab:lab restricted=false"))
machine.fail(agent("incus network create lab:escape --project default"))
machine.fail(agent("incus config set lab: core.https_address=:8443"))

machine.succeed(f"incus image import {metadata} {image} --alias fixture --project lab")
machine.succeed(f"incus image import {metadata} {image} --alias fixture --project default")
machine.succeed(f"incus create fixture operator-owned{vm_flag}")
machine.fail(agent("incus delete lab:operator-owned --project default --force"))
machine.succeed("incus info operator-owned")
machine.succeed(agent(f"incus launch lab:fixture lab:persistent{vm_flag}"))
guest_ready("persistent")
status, output = machine.execute(agent(f"incus launch lab:fixture lab:experiment{vm_flag} --ephemeral") + " 2>&1")
if status != 0:
    print(output)
    print(machine.succeed("free -m; cat /proc/pressure/{cpu,memory,io}; journalctl -k --no-pager | tail -100; journalctl -u incus --no-pager | tail -100"))
    raise Exception("second instance launch failed; see diagnostics above")
guest_ready("experiment")
guest_ready("persistent")
machine.succeed(agent("incus exec lab:experiment -- su - developer -c 'id -un' | grep -x developer"))
machine.succeed(agent("incus exec lab:experiment -- touch /tmp/experiment-marker"))
machine.fail(agent("incus exec lab:persistent -- test -e /tmp/experiment-marker"))
def denied(command, reason):
    # Test Driver captures stdout; Incus diagnostics go to stderr.
    status, output = machine.execute(agent(command) + " 2>&1")
    assert status != 0 and reason.lower() in output.lower(), (command, output)
before_config = json.loads(machine.succeed(agent("incus list lab: name=experiment --format=json")))[0]
denied("incus config device add lab:experiment host-etc disk source=/etc path=/host-etc", "not backed by a pool")
denied("incus config device add lab:experiment gpu gpu", "GPU devices are forbidden")
# Authorization restrictions remain; removed capacity budgets are not security controls.
if not vm:
    assert not before_config["expanded_config"].get("limits.cpu")
    assert not before_config["expanded_config"].get("limits.memory")
    assert not before_config["expanded_devices"]["root"].get("size")
# Discovery must work with the actual restricted credential, without sudo.
pool = json.loads(machine.succeed(agent("incus query 'lab:/1.0/storage-pools/default/resources?project=lab'")))
assert pool["space"]["total"] > 0, pool
resources = json.loads(machine.succeed(agent("incus query 'lab:/1.0/resources?project=lab'")))
assert resources["cpu"]["total"] > 0 and resources["memory"]["total"] > 0, resources
after_config = json.loads(machine.succeed(agent("incus list lab: name=experiment --format=json")))[0]
# Volatile config keys may change asynchronously (e.g. NIC state).
assert {k: v for k, v in after_config["config"].items() if not k.startswith("volatile.")} == {k: v for k, v in before_config["config"].items() if not k.startswith("volatile.")}
assert after_config["devices"] == before_config["devices"]
denied("incus config device add lab:experiment external nic nictype=physical parent=eth0 name=eth1", "Only managed network devices")
denied("incus network forward create lab:incuslab0 192.0.2.99", "permission for project")
if not vm:
    denied("incus config set lab:experiment security.privileged=true", "Privileged containers are forbidden")
    denied("incus config device add lab:experiment public proxy listen=tcp:0.0.0.0:18080 connect=tcp:127.0.0.1:8080", "Proxy devices are forbidden")
if vm:
    machine.fail(agent("incus config set lab:experiment raw.qemu=-nographic"))
# A real HTTP preview is reachable from the host without a public listener.
data = json.loads(machine.succeed(agent("incus list lab: name=experiment --format=json")))
assert len(data) == 1 and data[0]["name"] == "experiment", data
ips = [a["address"] for nic in data[0]["state"]["network"].values() for a in nic["addresses"] if a["family"] == "inet" and a["scope"] == "global"]
assert len(ips) >= 1, data
machine.wait_until_succeeds("curl -fsS http://" + ips[0] + ":8080/ | grep -F compute-host-fixture")
machine.succeed(agent("incus stop lab:experiment --force"))
machine.wait_until_fails(agent("incus info lab:experiment"))
machine.succeed(agent("incus exec lab:persistent -- systemctl is-active fixture-http"))

# The management daemon can restart without restarting the workload.
before = machine.succeed(agent("incus exec lab:persistent -- cat /proc/sys/kernel/random/boot_id")).strip()
pid = machine.succeed("incus info persistent --project lab | grep '^PID:'").strip()
machine.succeed("systemctl restart incus.service")
machine.wait_for_unit("incus-preseed.service")
guest_ready("persistent")
assert machine.succeed(agent("incus exec lab:persistent -- cat /proc/sys/kernel/random/boot_id")).strip() == before
assert machine.succeed("incus info persistent --project lab | grep '^PID:'").strip() == pid
assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == incumbent
denied("incus config device add lab:persistent host-etc disk source=/etc path=/host-etc", "not backed by a pool")
machine.fail(agent("incus info lab:operator-owned --project default"))
machine.succeed(agent("incus delete lab:persistent --force"))
machine.succeed("incus delete operator-owned")
machine.succeed(agent("incus list lab: --format=json | jq -e 'length == 0'"))
