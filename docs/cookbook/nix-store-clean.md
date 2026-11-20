---
type: Playbook
title: "nix-store-clean.md"
description: "Conservative Nix store cleanup and generation safety"
status: draft
source_revision: 22191670806242933bc156e4a5e0cd9ad3ea14f1
sources:
  - id: source-1
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/assets/nix-store-clean/cli.py
    title: "assets/nix-store-clean/cli.py"
  - id: source-2
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/50-features/nix-store-clean.nix
    title: "modules/50-features/nix-store-clean.nix"
---

# Nix Store cleanup on neko5 (safe maintenance)

## Why this changed

The previous `nix-store-clean-current-system` used `nix store delete --ignore-liveness` to remove every registered store path outside `/run/current-system`'s closure. That is **not** a correct liveness model: booted and pending-boot systems, user profiles, Home Manager, nix-direnv, other user GC roots, and running processes can keep paths live. A successful build of the next OS generation does not prove that unrelated roots were safe to delete.

The new tool **never bypasses GC liveness**. It first explains *which roots are keeping paths alive*, offers only a small number of constrained actions, and delegates store deletion to native `nix-store --gc`. It is intentionally **not** guaranteed to reclaim the same bytes as the unsafe former tool.

## Quick start

```sh
# Explicit read-only audit and machine-readable snapshot.
nix-store-clean-current-system audit
nix-store-clean-current-system audit --json > nix-store-audit.json

# Read-only review of your nix build `result` symlinks (no sudo).
nix-store-clean-current-system review-results
```

With no arguments, the cleaner opens the interactive menu on a terminal and audits otherwise. Native `gc` and optional `prune-system` are separate root operations. Each requires its own confirmation, either in the menu or with the explicit `--yes` flag. Pruning never invokes GC.

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
| `build-result` | Review shows owned `result` / `result-N` symlinks under the invoking user's home, outside hidden directories, whose resolved targets still match the root inventory. |
| `other` | Unclassified root; preserve. |

Run `review-results` without sudo, either directly on a terminal or in a pipeline. Menu option 2 prints the same read-only list without a second prompt. Each entry shows the project link and its observed store target. The display uses Python string quoting to make spaces and control characters visible.

A build or another process can retarget or remove a link after inspection. In the owning project, resolve the current link again with `readlink -e -- ./result` (use the actual basename, such as `result-2`). Check whether the project still uses that output. If you decide to retire the link, use the project's cleanup workflow, then rerun `nix-store-clean-current-system audit` or `nix-store --gc --print-roots` for a fresh inventory.

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

Before treating this as production-ready, run a real NixOS VM lifecycle test covering native GC, a staged boot, a mismatch between booted/current/profile targets, and return to a previous generation; then perform a controlled neko5 acceptance run. Fixtures cover read-only result review, native command selection, explicit GC and pruning confirmation, and refusal on boot mismatch. They do not substitute for those system tests.

## Primary references

- [Nix GC roots](https://nix.dev/manual/nix/2.31/package-management/garbage-collector-roots.html)
- [Nix garbage collection](https://nix.dev/manual/nix/2.34/command-ref/nix-store/gc.html)
- [Nix store deletion and liveness](https://nix.dev/manual/nix/2.34/command-ref/nix-store/delete.html)
- [Nix environment generations (`+N`)](https://nix.dev/manual/nix/2.30/command-ref/nix-env/delete-generations.html)
- [nix-direnv GC root behavior](https://github.com/nix-community/nix-direnv#readme)
- [NixOS VM integration testing](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html)

## Wiki context

The executable supports root-aware native GC. This runbook does **not** establish VM lifecycle or host acceptance. See [safety decisions](../memory/decisions.md) and [roadmap](../../ROADMAP.md).
