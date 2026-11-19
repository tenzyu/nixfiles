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
directory beside the host lock prevents later managed mutations when
completion was unconfirmed. Before clearing it, an authorized operator
must reconcile the host and guest jobs and their unit state and ensure
both managers have finished the previous request. The operator must hold
the lifecycle lock during that reconciliation and remove only the empty
guard directory. Never remove or replace the lifecycle inode.

The managed scope covers foreground invocations. Direct host or guest
control, timers, guest background jobs, and processes acting as root or
the game UID can bypass it. Establish absence of such writers before
treating the archive as an offline-consistent snapshot. The game UID still
has ordinary access to its older archives.

## Verification

`nix build -L --no-link .#checks.x86_64-linux.game-backup-minecraft` runs the
packaged operator and writer with inert lifecycle and privilege-transition
mocks. It injects I/O faults and restores the archive into an isolated
directory. The same packaged fixture can use the real `setpriv` by
building `(import ./test.nix { inherit pkgs; root = fixturePath;
mockIdentity = false; }).runner` and running it in a private user and
mount namespace with UID/GID 0 and 27009 mapped and a fresh tmpfs at
`fixturePath`. It still uses inert managers.

Host acceptance requires a separately authorized, dated test of the
native sudo wrapper and tmpfiles inode, the installed guest manager's
clean-stop properties, the destination's local persistent filesystem,
and the absence of bypass writers. An unexpected unit state or missing
privilege or filesystem capability is a refusal. The fixtures establish
descriptor retention and syscall ordering, with no power-loss claim.
