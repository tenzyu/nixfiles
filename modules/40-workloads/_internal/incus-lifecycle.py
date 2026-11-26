# NixOS test driver injects neko7; spec comes from the Nix fixture.
import shlex

workload = spec["name"]
guest_memory = spec["guestMemory"]
image = spec["image"]
candidate = spec["candidate"]
runtime_shell = spec["runtimeShell"]
justfile_source = spec["justfile"]
ops_source = spec["ops"]

neko7.start()
neko7.wait_for_unit("register-nix-paths.service")
neko7.wait_for_unit("incus-preseed.service")
neko7.succeed(f"test -c /dev/kvm; incus version; mkdir -p /root/fixture/tools; cp {justfile_source} /root/fixture/justfile; cp {ops_source} /root/fixture/tools/instance-ops.sh")
recipe = "cd /root/fixture && NEKO7_READINESS_TIMEOUT=900 just "


def exec_prefix(name):
    return "incus exec local:" + name + " --project default --mode=non-interactive --cwd / --env PATH=/run/wrappers/bin:/run/current-system/sw/bin -- "


def guest(name, command):
    return exec_prefix(name) + "/run/current-system/sw/bin/bash -ec " + shlex.quote(command) + " </dev/null"


def run(name, command):
    return neko7.succeed(guest(name, command)).strip()


def diagnose(name):
    # Test Driver uses errexit: independent probes preserve evidence
    # even if one CLI command or the agent is unresponsive.
    for command in [
        "incus info local:" + name + " --project default --show-log",
        "incus console local:" + name + " --project default --show-log",
        "free -m; cat /proc/pressure/{cpu,memory,io}; df -h; cat /proc/diskstats",
        "journalctl -u incus -n 100 --no-pager; journalctl -k -n 100 --no-pager",
        "ps -eLo pid,tid,stat,pcpu,wchan:32,comm | grep -E 'qemu|incus'",
        "incus config show local:" + name + " --expanded --project default",
        exec_prefix(name) + "/run/current-system/sw/bin/true </dev/null",
        exec_prefix(name) + "/run/current-system/sw/bin/systemctl --failed --no-pager </dev/null",
        exec_prefix(name) + "/run/current-system/sw/bin/systemctl status incus-agent --no-pager </dev/null",
        exec_prefix(name) + "/run/current-system/sw/bin/systemctl show -p ActiveState -p SubState -p Result -p MainPID -p ExecMainStatus -p NRestarts -p Type incus-agent syncthing immich-server postgresql redis-immich </dev/null",
        guest(name, "command -v ss >/dev/null && ss -lntp"),
        guest(name, "cat /proc/pressure/{cpu,memory,io}; free -m; df -h"),
        exec_prefix(name) + "/run/current-system/sw/bin/journalctl -b -u incus-agent --no-pager -n 100 </dev/null",
        exec_prefix(name) + "/run/current-system/sw/bin/journalctl -b -u immich-server --no-pager -n 150 </dev/null",
        exec_prefix(name) + "/run/current-system/sw/bin/journalctl -b -u postgresql -u redis-immich --no-pager -n 100 </dev/null",
        exec_prefix(name) + "/run/current-system/sw/bin/journalctl -b -u syncthing --no-pager -n 100 </dev/null",
        exec_prefix(name) + "/etc/neko7/readiness </dev/null",
    ]:
        status, output = neko7.execute("timeout -k 5s 30s bash -c " + shlex.quote(command) + " 2>&1", timeout=40)
        print(f"diagnostic: {command} (exit {status})\n{output}")


def ready(name):
    try:
        neko7.wait_until_succeeds("timeout -k 5s 30s " + exec_prefix(name) + "/etc/neko7/readiness </dev/null", timeout=900)
    except Exception:
        diagnose(name)
        raise


def new_instance(name):
    status, output = neko7.execute(recipe + shlex.join(["_new-image", workload, name, "16GiB", "2", guest_memory, image]) + " 2>&1", timeout=1200)
    if status != 0:
        print(output)
        diagnose(name)
        raise Exception("exact-image instance creation/readiness failed")
# Exact production image, no synthetic image substitution. The private
# artifact entrypoints are precisely the steps used by the public recipes
# after nix build; public build wrappers are tested separately.
# Two vCPUs let guest service initialization and the agent make progress
# concurrently. Production defaults and the hardware gate are unchanged.
new_instance("original")
# The production recipe already succeeded at the same readiness probe.
# The next command verifies actual guest exec and reads persistent identity.
original_id = run("original", "cat /etc/machine-id")
run("original", spec["seed"])
original_state = run("original", spec["verify"])
original_generation = run("original", "readlink -e /run/current-system")
uuid = neko7.succeed("incus config get local:original volatile.uuid --project default").strip()
assert uuid
# Concurrency and destination collision fail before stop or mutation.
neko7.succeed("flock /run/lock/neko7-instances/original.lock -c 'touch /tmp/lock-held; sleep 20' >/tmp/lock-log 2>&1 &")
neko7.wait_until_succeeds("test -f /tmp/lock-held")
neko7.fail(recipe + "backup original /root/locked-bundle")
neko7.succeed("test ! -e /root/locked-bundle")
neko7.wait_until_succeeds("flock -n /run/lock/neko7-instances/original.lock true")
neko7.succeed("mkdir -m 0700 /root/collision")
neko7.fail(recipe + "backup original /root/collision")
ready("original")
neko7.fail(recipe + shlex.join(["_update-system", "original", "/root/wrong-id", workload, "wrong-uuid", candidate]))
neko7.succeed("test ! -e /root/wrong-id")
# Separate instance identity without copying state, one running VM at a time.
neko7.succeed("incus stop local:original --project default")
new_instance("independent")
assert run("independent", "cat /etc/machine-id") != original_id
neko7.succeed("incus stop local:independent --project default")
neko7.succeed("incus start local:original --project default")
ready("original")
assert run("original", spec["verify"]) == original_state
# Update to a distinct test release with identical application version.
if spec["injectActivationFailure"]:
    # Fixture-only fault injection: preserve native calls except for the
    # activation boundary after the real profile mutation has completed.
    neko7.succeed("mkdir -p /root/fault-bin")
    neko7.succeed(f"cat >/root/fault-bin/sudo <<'EOF'\n#!{runtime_shell}\nfor arg in \"$@\"; do\n  case \"$arg\" in */bin/switch-to-configuration) touch /root/fault-activation-reached; exit 77;; esac\ndone\nexec /run/wrappers/bin/sudo \"$@\"\nEOF\nchmod 0700 /root/fault-bin/sudo")
    neko7.fail("cd /root/fixture && PATH=/root/fault-bin:$PATH NEKO7_READINESS_TIMEOUT=900 just " + shlex.join(["_update-system", "original", "/root/interrupted", workload, uuid, candidate]))
    neko7.succeed("test -f /root/fault-activation-reached")
    neko7.succeed("cd /root/interrupted && sha256sum -c SHA256SUMS")
    assert run("original", "readlink -e /nix/var/nix/profiles/system") == candidate
    assert run("original", "readlink -e /run/current-system") == original_generation
    assert run("original", spec["verify"]) == original_state
    # No activation ran; the fixture may safely reset only the release
    # pointer. This is not a general schema rollback procedure.
    run("original", "nix-env -p /nix/var/nix/profiles/system --set " + original_generation)
    ready("original")
neko7.succeed(recipe + shlex.join(["_update-system", "original", "/root/before-update", workload, uuid, candidate]))
assert run("original", "cat /etc/neko7/fixture-release") == "candidate"
assert run("original", "readlink -e /run/current-system") == candidate
assert run("original", spec["verify"]) == original_state
neko7.succeed("cd /root/before-update && sha256sum -c SHA256SUMS && jq -e --arg uuid " + shlex.quote(uuid) + " '.name == \"original\" and .uuid == $uuid' identity.json")
neko7.succeed(recipe + "backup original /root/after-update")
neko7.succeed("incus list local: name=original --format json | jq -e 'length == 1 and .[0].status == \"Stopped\"'")
# Incus import does not boot. Override the NIC before the first start,
# then assert no expanded NIC exists; never start a cloned identity online.
neko7.succeed("incus import local: /root/before-update/instance.tar.gz restore --project default -c boot.autostart=false")
neko7.succeed("incus config get local:restore boot.autostart --project default | grep -Fx false")
neko7.succeed("incus config device add local:restore eth0 none --project default")
neko7.succeed("incus list local: name=restore --format json | jq -e 'length == 1 and .[0].status == \"Stopped\" and ([.[0].expanded_devices[] | select(.type == \"nic\")] | length == 0)'")
neko7.succeed("incus start local:restore --project default")
ready("restore")
assert run("restore", "readlink -e /run/current-system") == original_generation
assert run("restore", spec["verify"]) == original_state
neko7.fail(guest("restore", "test -e /etc/neko7/fixture-release"))
neko7.succeed("incus stop local:restore --project default")
