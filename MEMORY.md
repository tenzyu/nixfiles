# nixfiles — agent memory index

**Purpose:** NixOS/Home Manager configuration for independently deployed hosts. Treat source declarations, evaluation, builds, activation, boot, and observed runtime as **different evidence tiers**. This file is a small retrieval index, not a copy of the Nix configuration or a live-machine inventory.

## Source of truth (2026-11-18)
- Read `flake.nix`, the relevant `modules/00-hosts/<host>/configuration.nix`, and the corresponding feature modules before changing behavior. The current feature selection uses `configurations.nixos.<host>.module`, `local.features`, `local.users` and an internal seed/materializer. This is the **existing implementation**, not an endorsement of its complexity.
- `neko5`: laptop, osu!lazer, Hyprland, remote build client. SplitCast capture is disabled. Preserve the known successful 1280×720 fullscreen/Direct Scanout path until independently checked.
- `neko7`: Proxmox VM, remote builder, NVIDIA, development services. The pinned T3 Code + Codex Home Manager service is declared on loopback port 3773; the OpenCode direnv integration is declared. A separate OpenCode service remains migration-gated; do not create a second writer to its state. SplitCast production role is declared with its Rust runtime candidate gated off.
- `neko6`: still declared as a NixOS-WSL host; user considers retirement acceptable, but runtime use and dependent references have not been disproved.
- Imported `splitcast` is a separate Flake. Its product code and packaging belong in its own repository; this repository owns only host integration and pinned consumer options.

## Retrieval — read only what this task needs
- [Wiki index](docs/index.md) → architecture, host status, decisions, targeted runbooks.
- [NixOS activation/rollback and outstanding gates](ROADMAP.md).
- [T3 Code deployment boundary](docs/t3code-neko7.md) and [OpenCode devShell integration](docs/opencode-devshells.md).
- [SplitCast consumer](docs/splitcast-consumer.md).
- [Dangerous operations](docs/decisions.md): filesystem migration, Nix-store pruning, privileged helpers, service switch and credentials.

## Execution contract
- Minimal source change → relevant `nix eval` / focused checks → comparison of affected host options and derivations → build when required. Record exact revision, command, result, limitations, and rollback.
- Do not use `nix flake check` as an unconditional PR gate: it can build unrelated heavyweight derivations. Do not claim a GitHub CI pass proves a service booted or worked on physical hardware.
- An approved `.envrc` with nix-direnv selects project tools for normal shell commands; avoid redundant per-command `nix develop -c` in an already initialized environment.
- Never automatically switch/boot/reboot hosts, open network listeners, enable capture, publish, merge, modify credentials, prune live Nix store roots, or migrate user data. These cross explicit operator approval boundaries.
- Keep personal host preferences and UI settings distinguishable from portable Nix modules. Prefer native NixOS/Home Manager options over a new custom framework. Preserve numbered top-level organization while simplifying the host import graph.
- Documentation or Dreaming updates must verify against code, preserve decisions and failed evidence, mark runtime uncertainty, avoid secrets, and change only genuinely stale or redundant claims.
