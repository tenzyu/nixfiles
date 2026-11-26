# Existing neko7 workload migration

## Target and authority

The host generation owns hardware, networking, native isolation mechanisms and stable service admission. A workload generation owns application release artifacts. The existing service identities and endpoints are preserved. Do not add a custom deployment manager, scheduler or registry; native Nix profiles are the release pointer and rollback mechanism.

| Declared capability | Target boundary | Mutable authority |
| --- | --- | --- |
| Minecraft | Existing native nspawn machine, independently built NixOS system profile | Existing /srv/minecraft, host service account, Tailscale state and lifecycle lock |
| T3 Code | Single native user systemd control plane, independently built T3/Codex runtime profile | Existing HOME, projects, provider auth, database, same 3773 and Serve 8445 |
| SplitCast production | Native manual user unit and TOML produced by the original upstream module, deployed together in an independent profile | Existing HOME credentials, peer settings and host GPU/audio; Rust parity gate remains false |
| Nix builder / SSH / Tailscale / Incus / rootless Docker / NVIDIA | Host or native user services | Existing daemon state, key restrictions and hardware |
| llama-cpp CUDA | Installed CLI, not a declared daemon | No service migration or invented daemon |
| ARK / Rust / OpenCode candidate | Disabled in source | No implicit activation; inspect unmanaged live units separately |

Incus remains the dynamic instance manager for new container/VM jobs and services. There is no project-specific execution adapter. Do not move existing Minecraft into Incus just to standardize the runtime name. Its existing nspawn machine has a production backup contract and separate data ownership. The migration separates its software release from the host generation. Moving T3 into a guest would make the host control plane depend on Incus and require a new management ingress. Keep T3 on the host. No new application or public listener is enabled.

## First cutover with operator approval

Before activation, inventory all live system and user units, `machinectl list`, `incus list --all-projects` if installed, rootless Docker, Serve state, and the current Minecraft guest/profile. This source migration cannot attest to undeclared manually started services. Record active unit PIDs, existing profiles, routes, application version and current system generation. Do not print credentials or raw Tailnet inventory externally.

Build all three artifacts at the reviewed checkout (do not update flake.lock as part of cutover):

```sh
nix build --no-link --print-out-paths .#neko7-minecraft-system
nix build --no-link --print-out-paths .#neko7-t3-runtime
nix build --no-link --print-out-paths .#neko7-splitcast-runtime
```

Seed the **Minecraft incumbent**, not a new server version. Confirm the lifecycle lock is not held and there is no unresolved job guard; use `game diagnose minecraft` and the existing backup procedure. The old and new host generation will use the same machine name, veth, mount paths, UID/GID and world. Do not create a second machine with these paths or the same Tailnet identity. As operator, from a known healthy running machine:

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

As tenzyu, in an SSH session independent of T3, use the existing XDG state directory (verify it matches the evaluated Home Manager stateHome):

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

The candidate host refuses activation with missing profiles. Do not run from a T3 session that would be interrupted. Explicitly approve the maintenance window, stop any manually active SplitCast production unit (do not start a gated unit), confirm Minecraft has a verified restorable backup, and activate the reviewed host generation. The first change of service definitions may restart the affected service; future workload software updates do not require a host rebuild. Keep Proxmox console access and prior system generation. Do not delete the old profile or data.

After cutover verify the Minecraft guest points to the incumbent profile, its Tailnet identity and world remain unchanged, and perform a real player login plus backup/recovery acceptance. Verify T3's HTTP response, paired client reconnect, provider login and a real project command; confirm Serve 8445 remains unchanged. Inspect SplitCast's generated unit and gate without executing it. Repeat existing SSH, Tailscale, Docker and Nix distributed-build acceptance. If any required check fails, revert the host generation and preserve all profiles/data for diagnosis.

## Independent releases after cutover

Build the artifact from a reviewed revision before changing its profile. Native Nix profile generations provide a GC root and rollback. Do not change the host declaration for an application version update.

Minecraft: coordinate the exclusive existing lifecycle lock and job guard throughout the stop/profile/start transaction. Take and verify a backup first; do not overlap with any game operator or raw container operation. Use the root-owned lock directory and do not clear an unconfirmed native job guard. Stop the entire container, confirm inactive, set the profile, start it and inspect the guest version, Tailscale connectivity and player login. Example commands below build before acquiring the existing lifecycle lock. Run the mutation block in a separate, approved operator session; a lock conflict, unresolved guard, failed stop or non-inactive machine aborts it. If interrupted during a native job, reconcile the manager state before retrying. Do not bypass the existing game operator's backup procedure:

```sh
candidate=$(nix build --no-link --print-out-paths .#neko7-minecraft-system)
# Only after a verified backup and a clean game diagnose result.
sudo bash -euo pipefail -s -- "$candidate" <<'SH'
candidate=$1
profile=/nix/var/nix/profiles/per-container/neko7-mc/system
lock=/run/nixfiles-game-locks/minecraft.lock
test -x "$candidate/init"
test -f "$lock" && test ! -L "$lock"
exec 9<"$lock"
flock -n -x 9
test ! -e "$lock.job" && test ! -L "$lock.job"
systemctl stop container@neko7-mc.service
test "$(systemctl show -p ActiveState --value container@neko7-mc.service)" = inactive
test "$(systemctl show -p MainPID --value container@neko7-mc.service)" = 0
nix-env --profile "$profile" --set "$candidate"
systemctl start container@neko7-mc.service
nixos-container run neko7-mc -- readlink -e /run/current-system
SH
```

On failed acceptance, reacquire the same exclusive lifecycle lock (including guard and job-state checks), stop the machine, use `sudo nix-env --profile "$profile" --rollback`, restart and verify. Software rollback does not revert world data. A newer Minecraft version may migrate saves irreversibly. Restore an independently verified backup only with explicit approval.

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

The CI workflow evaluates the actual host and all three artifact derivations, checks that their derivations are not referenced by the host generation, builds each artifact in an independent job, and tests a native nspawn profile upgrade from v1 to v2 and rollback to v1 with persistent state, host-generation identity and an unrelated service PID unchanged. It does not replay live credentials, prove production data/schema rollback, or attest to hardware/media performance. The real deployment gate is the approved first cutover above.
