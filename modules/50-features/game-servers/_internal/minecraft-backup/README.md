# Managed Minecraft backups

Use the installed `game backup minecraft` command. It uses the existing
NixOS operator authorization and fixed `local.gameOperations.minecraft`
policy. Backup needs a running container and a readable guest unit. If the
unit is cleanly inactive, it stays inactive. If the unit is running, the
operator preflights the archive as the game UID and then stops the guest
unit. The operator verifies the stopped unit's job, status, cgroup and exit
record before starting the writer. An inactive container leaves guest
quiescence unknown and the backup refuses without starting it.

The host takes a nonblocking exclusive flock on the root-owned tmpfiles
inode and keeps it through managed start, stop, restart, send, console,
exec, and backup. Update still directs the operator to declarative
deployment. Authorization happens before opening the lock. The fixed
`setpriv` invocation then drops to the configured game UID/GID and clears
supplementary groups. The writer verifies the inherited descriptor before
preflight. Guest admin payloads receive no lock descriptor. Their foreground
waiter retains it while they run.

The archive scope is the unchanged game-owned backups directory. Its
canonical ancestry must belong to root or the game UID and disallow writes
by other users and groups. The writer bootstraps its own `.safety.lock`
under that UID and uses the Shell core to create a private stage, sync the
verified archive, link the final leaf without replacement, and sync the
directory. The timestamp format is unchanged. An occupied same-second
name is a conflict. Each new archive has mode 0600 and contains the
`survival/` tree and regular `world/level.dat` data. Restore declarative
settings through Nix.

Only confirmed publication allows a previously running unit to resume.
An archive error or an uncertain publication leaves it in the stopped
state observed before capture. A failed resume is reported independently
of archive publication. Inspect the named archive and any retained stage
after an unknown outcome. Keep existing finals and the lock inode.

A native systemd job may outlive every client during hard interruption or
loss of the manager connection. The root-only `minecraft.lock.job`
directory beside the host lock is created before dispatch and keeps later
managed mutations out when the waiter cannot confirm success. The waiter
ignores terminal interruption signals and retains the flock while the
native command runs. A hard kill or a lost reply can still leave just the
guard. A nonzero native command reports the manager, verb and unit, and
retains the guard even if the manager may have rejected the request.

The managed scope covers foreground invocations. Direct host or guest
control, timers, guest background jobs, and processes acting as root or
the game UID can bypass it. Establish absence of such writers before
treating the archive as an offline-consistent snapshot. The game UID still
has ordinary access to its older archives.

## Diagnose and recover

Run `game diagnose minecraft` from the host. It prints the guard's path and
metadata, the host container and guest service unit properties, and both
managers' current job queues. It works while the lifecycle lock is held and
while admission is blocked. An unavailable query makes the command exit
69 and still report what it could read. The command leaves the guard,
services and archives untouched. Keep its output and the previous command's
output when escalating an unknown outcome.

Only an authorized host operator can clear the guard. Coordinate with
other operators so nothing bypasses the lifecycle lock during recovery.
On `neko7`, open a root Bash shell and acquire the existing inode read-only.
The shell must stay open through inspection and clearance.

```bash
sudo bash --noprofile --norc
lock_dir=/run/nixfiles-game-locks
lock=$lock_dir/minecraft.lock
guard=$lock.job
[[ $(realpath -e -- "$lock_dir") == "$lock_dir" &&
   $(stat -fLc '%T' -- "$lock_dir") == tmpfs ]] || exit 1
for dir in / /run "$lock_dir"; do
  metadata=$(stat -Lc '%u:%a' -- "$dir") || exit 1
  [[ ${metadata%:*} == 0 ]] && (( (8#${metadata#*:} & 022) == 0 )) || exit 1
done
[[ $(stat -Lc '%U:%G:%a' -- "$lock_dir") == root:wheel:750 &&
   -f $lock && ! -L $lock &&
   $(stat -Lc '%U:%G:%a:%h' -- "$lock") == root:wheel:440:1 ]] || exit 1
exec 9<"$lock" || exit 1
[[ $lock -ef /proc/self/fd/9 ]] && flock -xn 9 || exit 1
[[ -d $guard && ! -L $guard && $(stat -c '%u:%a' -- "$guard") == 0:700 ]] || exit 1
/run/current-system/sw/bin/game diagnose minecraft
```

- Correlate the prior operation with the guard timestamp, queued job IDs and
  host and guest unit journals. Inspect related jobs and any unit transition
  that could still take effect. For example, use `journalctl -b -u
  container@neko7-mc.service` on the host and `nixos-container run neko7-mc --
  /run/current-system/sw/bin/journalctl -b -u minecraft-server-survival.service`
  for the existing guest. These commands need no service start.
- Keep the guard if a relevant request or its effects can still run, the
  manager is unreachable, or the evidence is ambiguous. If the container
  is down, establish from host evidence that the old guest manager and its
  processes exited and that the host request has settled. A failed guest
  query alone does not establish that. A missing client PID, a single
  `Job=0` or an empty job listing does not settle an earlier request. Do
  not cancel jobs or change service state just to make the checks pass.
- Once you have established that the previous requests and transitions have
  settled, run `rmdir -- "$guard"` in the same root shell, then `exit` to
  release the flock. `rmdir` refuses a nonempty guard. Leave the lifecycle
  inode in place. This only reopens admission. Archive verification and any
  decision to start the game are separate. If a failed or interrupted
  backup left the guest stopped, leave it stopped pending that decision.
  Preserve existing finals and any retained stage while checking publication.

For an unconfirmed archive, use the exact path printed by `game backup`.
Inspect the final and any retained stage under the archive account with
`gzip -t -- "$candidate"` and `tar -tzf "$candidate"`. Look for the
expected `survival/world/level.dat`. A readable archive helps recover data,
but does not establish that publication or the directory flush completed.
Leave the result unconfirmed until it has been reconciled separately.

## Why keep the guard

The pinned Nixpkgs packages systemd 260.5. In that release the manager
enqueues a job and then replies with its object path. The synchronous
client subscribes before dispatch and waits for the corresponding
`JobRemoved`. Disconnect closes the client's bus and may fail its wait.
Service jobs are outside the job GC used for units like devices, even if
the bus tracker loses its last client. `ListJobs` is a snapshot of the
current queue. [Nixpkgs package](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/pkgs/os-specific/linux/systemd/default.nix#L202-L211),
[manager enqueue and reply](https://github.com/systemd/systemd/blob/v260.5/src/core/dbus-unit.c#L1985-L2010),
[systemctl dispatch and wait](https://github.com/systemd/systemd/blob/v260.5/src/systemctl/systemctl-start-unit.c#L388-L430),
[disconnect handling](https://github.com/systemd/systemd/blob/v260.5/src/shared/bus-wait-for-jobs.c#L48-L78),
[job GC eligibility](https://github.com/systemd/systemd/blob/v260.5/src/core/job.c#L1465-L1476),
[manager job API](https://github.com/systemd/systemd/blob/v260.5/man/org.freedesktop.systemd1.xml#L1288-L1294),
[current job queue](https://github.com/systemd/systemd/blob/v260.5/man/org.freedesktop.systemd1.xml#L1425-L1439).

`--no-block` returns at admission. `--job-mode=fail` applies to conflicting
queued work and provides no exclusion during archive creation. Canceling a
job can leave a unit transition in progress. Freezing stops scheduling the
unit's processes, so it does not produce a clean application stop and is
automatically undone before a unit job executes. A unit path condition
is tested at start and `RefuseManualStart=` still allows activation by
dependencies. A transient coordinator would still need to fence the other
managed entry points and cross the host and guest manager boundary. The
fixed flock and the same-boot guard retain those admission semantics with
the existing native lifecycle owners. [systemctl options](https://github.com/systemd/systemd/blob/v260.5/man/systemctl.xml#L2215-L2249),
[blocking semantics](https://github.com/systemd/systemd/blob/v260.5/man/systemctl.xml#L2424-L2433),
[cancellation](https://github.com/systemd/systemd/blob/v260.5/man/org.freedesktop.systemd1.xml#L1638-L1649),
[freeze](https://github.com/systemd/systemd/blob/v260.5/man/systemctl.xml#L651-L663),
[manual start policy](https://github.com/systemd/systemd/blob/v260.5/man/systemd.unit.xml#L1011-L1025),
[path conditions](https://github.com/systemd/systemd/blob/v260.5/man/systemd.unit.xml#L1744-L1754),
[transient units](https://github.com/systemd/systemd/blob/v260.5/man/systemd-run.xml#L69-L81),
[pinned container transport](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/pkgs/by-name/ni/nixos-container/nixos-container.pl#L383-L389),
[nsenter child exit handling](https://github.com/util-linux/util-linux/blob/v2.42.4/sys-utils/nsenter.c#L563-L579).

## Verification

`nix build -L --no-link .#checks.x86_64-linux.game-backup-minecraft` runs the
packaged operator and writer with inert lifecycle and privilege-transition
mocks. It injects I/O faults and restores the archive into an isolated
directory. The same packaged fixture can use the real `setpriv` by
building `(import ./test.nix { inherit pkgs; root = fixturePath;
mockIdentity = false; }).runner` and running it in a private user and
mount namespace with UID/GID 0 and 27009 mapped and a fresh tmpfs at
`fixturePath`. It still uses inert managers.

Real host acceptance is **NOT RUN**. It requires a separately authorized,
dated test of the native sudo wrapper and tmpfiles inode, the installed
guest manager's clean-stop properties, the destination's local persistent
filesystem, and the absence of bypass writers. An unexpected unit state
or missing privilege or filesystem capability is a refusal. The fixtures
establish descriptor retention and syscall ordering, with no power-loss
claim.
