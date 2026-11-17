# Nix Store cleanup on neko5 (safe maintenance)

## Why this changed

The previous `nix-store-clean-current-system` used `nix store delete --ignore-liveness` to remove every registered store path outside `/run/current-system`'s closure. That is **not** a correct liveness model: booted and pending-boot systems, user profiles, Home Manager, nix-direnv, other user GC roots, and running processes can keep paths live. A successful build of the next OS generation does not prove that unrelated roots were safe to delete.

The new tool **never bypasses GC liveness**. It first explains *which roots are keeping paths alive*, offers only a small number of constrained actions, and delegates store deletion to native `nix-store --gc`. It is intentionally **not** guaranteed to reclaim the same bytes as the unsafe former tool.

## Quick start

```sh
# Runs an interactive menu when connected to a terminal; otherwise audits only.
nix-store-clean-current-system

# Explicit read-only audit and machine-readable snapshot.
nix-store-clean-current-system audit
nix-store-clean-current-system audit --json > nix-store-audit.json

# Guided review of own nix build `result` symlinks (NO sudo).
nix-store-clean-current-system review-results

# Native GC, retaining every existing live root. Use sudo only for system operations.
sudo nix-store-clean-current-system gc --yes

# Optional rollback retention policy: keep at least 3 system profile generations.
# Allowed only after booted/current/system-profile targets all match.
sudo nix-store-clean-current-system prune-system --keep-generations 3 --yes
sudo nix-store-clean-current-system gc --yes
```

To reduce accidental deletion, `prune-system` retains at least **two** generations, requires root privileges and explicit confirmation, and refuses to run if the three system links are missing, unregistered, or point at different store paths. The `+N` generation-retention semantics follow the Nix `nix-env --delete-generations` documentation: generations **newer** than the active profile are also retained. Because `nix-env` has `--dry-run` support, you can independently preview the effect with:

```sh
sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +3 --dry-run
```

> **Important:** The system-profile pruning action can remove **bootloader rollback choices**; it is optional, not part of ordinary GC, and is blocked while a different next-boot configuration is staged. It does not delete user generations or control Home Manager. A separate NixOS reconstruction test is still required before enabling automated generation-pruning.

## What the audit means

`audit` reports the currently booted, activated and system-profile targets, the root groups returned by `nix-store --gc --print-roots`, a count of **GC-dead** store paths, and filesystem free space. Use `--json` to consume the report in a future storage workbench. All root categories are *heuristics*, not proof that a root can be removed. It does **not** calculate a reliable number of bytes recoverable by removing an individual root; closures share objects and store files may be hardlinked.

| Classification | Policy |
| --- | --- |
| `system` | Never remove in this tool. Includes current/booted and system profiles. |
| `runtime` | Running processes can keep store paths live; never remove here. |
| `profile` | Nix profiles and Home Manager; never remove here. |
| `direnv` | Persistent dev-shell GC roots; show for investigation, do not remove automatically. |
| `build-result` | Only plain `result` / `result-N` symlinks under the invoking user's home directory are eligible for **interactive review**. |
| `other` | Unclassified root; preserve. |

`review-results` is the only action that unlinks a user's original symlink. It runs **without sudo**, requires an interactive terminal, lists the exact user-owned links, asks for specific item numbers and the literal confirmation `UNLINK`, then rechecks ownership, symlink target, parent containment and GC-root presence. It does not delete any `/nix/store` paths. Recreate a deliberately removed `result` via the project's `nix build` or other original build command; doing so after GC may require fetching or rebuilding the output. For safety, this action does not touch Home Manager, nix-direnv or profiles.

## After the earlier unsafe 11 GiB deletion

Before rebooting, build and register the intended configuration using your normal `nh os boot` workflow and verify all expected system paths are registered:

```sh
for link in /run/booted-system /run/current-system /nix/var/nix/profiles/system; do
  target=$(readlink -e "$link") || { echo "MISSING $link"; exit 1; }
  nix-store --query --requisites "$target" >/dev/null || exit 1
  echo "$link -> $target"
done
findmnt /boot
bootctl list
```

This is a **pre-reboot check**, not proof that the kernel/initrd will boot or that unrelated Home Manager/development environments are intact. Do not run the old `--delete --yes` command again. The new program intentionally rejects `--delete`, `--allow-booted-diff`, `--root`, `--keep` and other old override flags.

## Verification

Fast deterministic tests (no Nix daemon required):

```sh
python3 -m unittest discover -s assets/nix-store-clean -v
```

Nix package integration check (on a Nix machine):

```sh
nix build .#checks.x86_64-linux.nix-store-clean
```

Before treating this as production-ready, run a real NixOS VM lifecycle test covering native GC, a staged boot, a mismatch between booted/current/profile targets, and return to a previous generation; then perform a controlled neko5 acceptance run. The included tests cover parsing, user-owned symlink constraints, explicit confirmation and fail-closed rules, but **do not substitute for those system tests**.

## Primary references

- [Nix GC roots](https://nix.dev/manual/nix/2.31/package-management/garbage-collector-roots.html)
- [Nix garbage collection](https://nix.dev/manual/nix/2.34/command-ref/nix-store/gc.html)
- [Nix store deletion and liveness](https://nix.dev/manual/nix/2.34/command-ref/nix-store/delete.html)
- [Nix environment generations (`+N`)](https://nix.dev/manual/nix/2.30/command-ref/nix-env/delete-generations.html)
- [nix-direnv GC root behavior](https://github.com/nix-community/nix-direnv#readme)
- [NixOS VM integration testing](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html)
