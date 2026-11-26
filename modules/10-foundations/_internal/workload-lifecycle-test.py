import shlex

profile = spec["profile"]
first = spec["first"]
second = spec["second"]
switch = spec["switch"]


def transition(expected, *args, expect_timeout=False):
    command = shlex.join(["bash", switch, "fixture", expected, *args])
    leader = machine.succeed("machinectl show fixture --property=Leader --value").strip()
    assert leader.isdecimal() and int(leader) > 1, leader
    # Observe a stalled stop before host systemd destroys its process state.
    # The observer never delays the stop or changes the guest's job queue.
    body = f"""
set +e
scratch=$(mktemp -d) || exit 1
(
  sleep 2
  if test ! -e "$scratch/done" && test "$(systemctl show -p ActiveState --value container@fixture.service)" = deactivating; then
    echo '--- pending shutdown: host ---'
    systemctl list-jobs --no-pager --full
    systemctl show container@fixture.service --all
    machinectl show fixture --all
    ps -eLo pid,tid,stat,wchan:32,comm
    findmnt --kernel --noheadings --raw --output TARGET,SOURCE,FSTYPE | grep -E '/run/systemd/nspawn|/var/lib/nixos-containers/fixture'
    echo '--- pending shutdown: guest leader {leader} ---'
    for item in status cgroup mountinfo stack; do cat /proc/{leader}/$item; done
    ls -l /proc/{leader}/ns
    timeout -k 1s 2s nsenter -t {leader} --mount --pid --root --wd -- /run/current-system/sw/bin/systemctl list-jobs --no-pager --full
    timeout -k 1s 2s nsenter -t {leader} --mount --pid --root --wd -- /run/current-system/sw/bin/journalctl -b -n 100 --no-pager
  fi
) </dev/null > "$scratch/diagnostics" 2>&1 &
observer=$!
{command} 2>&1
status=$?
touch "$scratch/done"
wait "$observer"
cat "$scratch/diagnostics"
rm -rf "$scratch"
exit "$status"
"""
    status, output = machine.execute("bash -c " + shlex.quote(body), timeout=180)
    print(output)
    if expect_timeout:
        assert status != 0 and "Profile switch refused:" in output and "Result=timeout" in output, (status, output)
    else:
        assert status == 0, (status, output)


machine.start()
machine.wait_for_unit("incumbent.service")
system = machine.succeed("readlink -e /run/current-system").strip()
pid = machine.succeed("systemctl show -p MainPID --value incumbent.service").strip()

machine.succeed("systemctl start container@fixture.service")
machine.fail("systemctl is-active --quiet container@fixture.service")
machine.succeed("mkdir -p /nix/var/nix/profiles/per-container/fixture")
machine.succeed(f"nix-env --profile {profile} --set {first}")
machine.succeed("systemctl start container@fixture.service")
machine.wait_until_succeeds("nixos-container run fixture -- grep -x v1 /etc/workload-release")
machine.succeed("nixos-container run fixture -- sh -c 'echo persisted > /var/lib/workload-state; sync'")

transition(first, "--set", second)
machine.wait_until_succeeds("nixos-container run fixture -- grep -x v2 /etc/workload-release")
assert machine.succeed("nixos-container run fixture -- readlink -e /run/current-system").strip() == second
machine.succeed("nixos-container run fixture -- grep -x persisted /var/lib/workload-state")
assert machine.succeed("readlink -e /run/current-system").strip() == system
assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == pid

transition(second, "--rollback")
machine.wait_until_succeeds("nixos-container run fixture -- grep -x v1 /etc/workload-release")
assert machine.succeed("nixos-container run fixture -- readlink -e /run/current-system").strip() == first
machine.succeed("nixos-container run fixture -- grep -x persisted /var/lib/workload-state")
assert machine.succeed("readlink -e /run/current-system").strip() == system
assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == pid

# Fault injection runs last. Only the disposable fixture gets a short timeout.
# A real guest service blocks its shutdown; no systemctl test double is used.
machine.succeed("nixos-container run fixture -- systemctl start shutdown-blocker.service")
machine.succeed("nixos-container run fixture -- systemctl is-active --quiet shutdown-blocker.service")
machine.succeed("mkdir -p /run/systemd/system/container@fixture.service.d; printf '[Service]\\nTimeoutStopSec=15s\\n' > /run/systemd/system/container@fixture.service.d/99-fault.conf; systemctl daemon-reload")
generations = machine.succeed(f"nix-env --profile {profile} --list-generations")
started = machine.succeed("systemctl show -p ExecMainStartTimestampMonotonic --value container@fixture.service").strip()
transition(first, "--set", second, expect_timeout=True)
machine.succeed("systemctl show -p Result --value container@fixture.service | grep -Fx timeout")
machine.fail("systemctl is-active --quiet container@fixture.service")
assert machine.succeed(f"readlink -e {profile}").strip() == first
assert machine.succeed(f"nix-env --profile {profile} --list-generations") == generations
assert machine.succeed("systemctl show -p ExecMainStartTimestampMonotonic --value container@fixture.service").strip() == started
machine.succeed("grep -Fx persisted /var/lib/nixos-containers/fixture/var/lib/workload-state")
assert machine.succeed("readlink -e /run/current-system").strip() == system
assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == pid
# An attempted rollback cannot erase the failure and proceed either.
machine.fail(shlex.join(["bash", switch, "fixture", first, "--rollback"]))
assert machine.succeed(f"readlink -e {profile}").strip() == first
assert machine.succeed(f"nix-env --profile {profile} --list-generations") == generations
assert machine.succeed("systemctl show -p ExecMainStartTimestampMonotonic --value container@fixture.service").strip() == started
