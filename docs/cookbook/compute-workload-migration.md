# Migrate existing neko7 workloads

## Target and authority

Review the [workload ownership and release design](compute-workload-design.md#target-and-authority) before you change a profile.

## First cutover with operator approval

Before activation, inventory all live system and user units, `machinectl list`, `incus list --all-projects` if installed, rootless Docker, Serve state, and the current Minecraft guest/profile. This source migration cannot attest to undeclared manually started services. Record active unit PIDs, existing profiles, routes, application version and current system generation. Do not print credentials or raw Tailnet inventory externally.

Do not update `flake.lock` during cutover. Build all three artifacts at the reviewed checkout:

```sh
nix build --no-link --print-out-paths .#neko7-minecraft-system
nix build --no-link --print-out-paths .#neko7-t3-runtime
nix build --no-link --print-out-paths .#neko7-splitcast-runtime
```

Seed the profile with the currently running Minecraft system. Do not install a new server version. Run `game diagnose minecraft`. Confirm that no process holds the lifecycle lock and that no unresolved job guard exists. Follow the existing backup procedure. The old and new host generation will use the same machine name, veth, mount paths, UID/GID and world. Do not create a second machine with these paths or the same Tailnet identity. As operator, from a known healthy running machine:

```sh
old=$(sudo nixos-container run neko7-mc -- readlink -e /run/current-system)
test -n "$old" && test -x "$old/init" || exit 1
p=/nix/var/nix/profiles/per-container/neko7-mc/system
sudo test ! -e "$p" && sudo test ! -L "$p" || {
	echo "Existing profile: inspect and reconcile; do not overwrite blindly" >&2
	exit 1
}
sudo mkdir -p "$(dirname "$p")"
sudo nix-env --profile "$p" --set "$old"
```

If a profile already points at the same incumbent, retain it rather than reseeding. For T3 and SplitCast, compare the pinned packages, unit and generated TOML against the incumbent. Existing T3 sessions and provider credentials stay in the original account; no new HOME or T3 database is created. Preserve the incumbent unit and private generated configuration receipts. If the live versions differ, stop and reconcile instead of blindly installing a downgrade.

Open an SSH session as `tenzyu`, independent of T3. Verify that the existing XDG state directory matches the evaluated Home Manager `stateHome`. Run:

```sh
pdir="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles"
mkdir -p "$pdir"
t3=$(nix build --no-link --print-out-paths .#neko7-t3-runtime)
sc=$(nix build --no-link --print-out-paths .#neko7-splitcast-runtime)
test -x "$t3/bin/t3" && test -x "$t3/bin/codex" || exit 1
test -r "$sc/share/systemd/user/splitcast-production.service" || exit 1
# First enrollment only; inspect existing profiles if either exists.
for p in "$pdir/t3-runtime" "$pdir/splitcast-production"; do
	test ! -e "$p" && test ! -L "$p" || exit 1
done
nix-env --profile "$pdir/t3-runtime" --set "$t3"
nix-env --profile "$pdir/splitcast-production" --set "$sc"
```

The candidate host refuses activation with missing profiles. Do not run from a T3 session that would be interrupted. Explicitly approve the maintenance window, stop any manually active SplitCast production unit (do not start a gated unit), confirm Minecraft has a verified restorable backup, and activate the reviewed host generation. The first change to service definitions may restart the affected service. Future workload software updates do not require a host rebuild. Keep Proxmox console access and prior system generation. Do not delete the old profile or data.

After cutover verify the Minecraft guest points to the incumbent profile, its Tailnet identity and world remain unchanged, and perform a real player login plus backup/recovery acceptance. Verify T3's HTTP response, paired client reconnect, provider login and a real project command; confirm Serve 8445 remains unchanged. Inspect SplitCast's generated unit and gate without executing it. Repeat existing SSH, Tailscale, Docker and Nix distributed-build acceptance. If any required check fails, revert the host generation and preserve all profiles/data for diagnosis.

## Independent releases after cutover

Build the artifact from a reviewed revision before changing its profile. Native Nix profile generations provide a GC root and rollback. For an application version update, leave the host declaration unchanged.

Minecraft: coordinate the exclusive existing lifecycle lock and job guard throughout the stop/profile/start transaction. Take and verify a backup first. Do not overlap with any game operator or raw container operation. Use the root-owned lock directory and do not clear an unconfirmed native job guard. Run the switch script from the reviewed checkout under the same lock. The script refuses to change the profile if systemd reports a failed stop, a pending job, remaining processes, a registered machine, or a residual nspawn mount. Do not reset a failed unit or remove a mount to bypass that refusal.

```sh
candidate=$(nix build --no-link --print-out-paths .#neko7-minecraft-system)
profile=/nix/var/nix/profiles/per-container/neko7-mc/system
expected=$(sudo readlink -e "$profile")
switch=$(realpath tools/nspawn-profile-switch.sh)
# Only after a verified backup and a clean game diagnose result.
sudo bash -euo pipefail -s -- "$switch" "$expected" --set "$candidate" <<'SH'
switch=$1
expected=$2
shift 2
lock=/run/nixfiles-game-locks/minecraft.lock
test -f "$lock" && test ! -L "$lock"
exec 9<"$lock"
flock -n -x 9
test ! -e "$lock.job" && test ! -L "$lock.job"
bash "$switch" neko7-mc "$expected" "$@"
nixos-container run neko7-mc -- readlink -e /run/current-system
SH
```

Verify the guest version, Tailnet connectivity and player login. For native generation rollback, use the same locked block with `--rollback` instead of `--set "$candidate"` and the explicitly verified current release as `expected`. Inspect the generation list first. Do not repeat a relative rollback blindly. If interrupted, reconcile the native unit, mount, and profile state under the lock before choosing a new operation. Software rollback does not revert world data. A newer Minecraft version may migrate saves irreversibly. Restore an independently verified backup only with explicit approval.

T3: use an independent SSH session, stop the same user unit, advance its profile, then start that same unit. Roll back the profile and restart if the new server fails acceptance. A newer T3 database schema may require its own application backup/recovery; no automatic state downgrade.

```sh
candidate=$(nix build --no-link --print-out-paths .#neko7-t3-runtime)
profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/t3-runtime"
systemctl --user stop t3code-neko7.service
nix-env --profile "$profile" --set "$candidate"
systemctl --user start t3code-neko7.service
```

SplitCast: stop any active unit first, build the pinned profile, advance it, and run `systemctl --user daemon-reload`. This profile deliberately preserves the upstream migration gate and manual activation; do not start it merely because a build passed. Roll back using `nix-env --profile "$profile" --rollback` and daemon-reload. GPU/media parity and any future activation require separate authorization.

Native profile updates are performed by the operator, not automatically by arbitrary Coding Agents. The agent's dynamic Incus lab capability remains restricted. No custom lifecycle API is introduced.

## Evidence

See the [workload migration test scope](compute-workload-design.md#evidence). Complete the approved first cutover before you claim production acceptance.
