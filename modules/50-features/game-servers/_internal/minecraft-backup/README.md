# Back up Minecraft and recover failed operations

Use the installed `game backup minecraft` command. It uses the existing
NixOS operator authorization and fixed `local.gameOperations.minecraft`
policy. Before you run a backup, confirm that the container is running and the guest unit is readable. If the
unit is cleanly inactive, it stays inactive. If the unit is running, the
operator preflights the archive as the game UID and then stops the guest
unit. The operator verifies the stopped unit's job, status, cgroup and exit
record before starting the writer. If the container is inactive, the backup command cannot verify that guest writers have stopped. It refuses without starting the container.

The host takes a nonblocking exclusive flock on the root-owned tmpfiles
inode and keeps it through managed start, stop, restart, send, console,
exec, and backup. Update still directs the operator to declarative
deployment. The operator checks authorization before opening the lock. The fixed
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

The backup command prints the archive path before preflight or any service stop. Save that output to identify the archive after an interruption.
Only confirmed publication allows a previously running unit to resume.
If archive creation fails or publication remains uncertain, the backup command leaves the guest unit stopped. A failed resume is reported independently
of archive publication. Inspect the named archive and any retained stage
after an unknown outcome. Keep existing finals and the lock inode.

A native systemd job may outlive every client during hard interruption or
loss of the manager connection. The root-only `minecraft.lock.job`
directory beside the host lock lives on the current boot's `/run` tmpfs.
The operator creates it before dispatch. If the waiter cannot confirm success,
the guard blocks later managed mutations. The waiter
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

Only an authorized host operator can clear the guard. Before recovery, coordinate with other operators to prevent operations that bypass the lifecycle lock.
On `neko7`, open a root Bash shell and acquire the existing inode read-only.
Keep the shell open until you finish inspection and clear the guard.

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
  processes exited and that the host request has settled. A failed guest query alone does not prove that the old manager and its processes exited or that the host request settled. A missing client PID, a single
  `Job=0` or an empty job listing does not settle an earlier request. Do
  not cancel jobs or change service state just to make the checks pass.
- Once you have established that the previous requests and transitions have
  settled, run `rmdir -- "$guard"` in the same root shell, then `exit` to
  release the flock. `rmdir` refuses a nonempty guard. Leave the lifecycle
  inode in place. This only reopens admission. Archive verification and any
  decision to start the game are separate. If a failed or interrupted
  backup left the guest stopped, leave it stopped pending that decision.
  Preserve existing finals and any retained stage while checking publication.

For an unconfirmed archive, use the path printed as `Archive target` by
`game backup minecraft`. Treat it as the candidate to inspect.
Inspect the final and any retained stage under the archive account with
`gzip -t -- "$candidate"` and `tar -tzf "$candidate"`. Look for the
expected `survival/world/level.dat`. A readable archive helps recover data.
It does not prove that publication or the directory flush completed.
Leave the result unconfirmed until it has been reconciled separately.

## Why keep the guard

See [why the Minecraft job guard is required](guard-design.md).

## Verification

Follow the [Minecraft backup verification procedure](verify.md) before you claim acceptance.
