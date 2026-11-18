# nixfiles — retrieval index

**Purpose:** a compact map for agents working on this personal NixOS / Home Manager repository. This file is **not** host telemetry, a changelog, or a duplicate of feature modules. Review [AGENTS.md](AGENTS.md) for execution limits.

## Read the right source

- **Host change:** `flake.nix` → `modules/00-hosts/<host>/configuration.nix` → selected `modules/50-features/<domain>/` or `modules/60-integrations/`. See [architecture](docs/architecture.md).
- **Nix options / compose helpers:** [native option ownership](docs/feature-options.md), [composition contracts](docs/composition.md), and `lib/`. Do not conflate shallow `//` updates with native module merge priorities.
- **Runtime, migration or secret question:** [host inventory](docs/host-state.md), [decisions](docs/decisions.md), then the exact [Wiki runbook](docs/index.md).
- **What remains blocked:** [roadmap](ROADMAP.md). Past `docs/log.md` entries do not authorize pending work.

## Source snapshot (2026-11-18; Git `438aa02b426d`)

- `neko5`: laptop, Hyprland, osu!lazer, remote build client. `splitcast-capture` disabled. Preserve known Direct Scanout success conditions; do not assert measured input-to-photon gains.
- `neko6`: declared NixOS-WSL CLI host. Original installation `system.stateVersion` lineage remains unverified; do not silently retire it.
- `neko7`: Proxmox guest, remote builder, T3 Code, SplitCast **consumer**. `game-minecraft = true`, `game-ark = false`, `game-rust = false`, `game-srv = true`; Minecraft's declared data root is `/srv/minecraft`. A dated acceptance record exists in the [storage runbook](docs/game-server-srv-migration.md); fresh state requires fresh observation.
- `sops-nix.enable = true` is declared on neko5 and neko7. This is provider selection, **not** proof of a specific secret, key file, decryption, or successful tailnet enrollment.
- SplitCast sources/tests/PR acceptance are owned by `tenzyu/splitcast`. Nixfiles only pins/consumes its flake.

## Fixed authoring and execution boundaries

- Keep `configurations.nixos.<host>.module`, `local.features.<name>.enable`, `local.users.<user>.features.<name>.enable`, typed editor completion and explicit per-host choices. Do **not** replace these with host-side import arrays or opaque bundles.
- Prefer native NixOS/Home Manager options and Nixpkgs `lib`; `lib/composition.nix` names value stages and detects accidental attrset overwrites but is **not** another module system.
- When direnv has entered the dev shell, run ordinary commands directly. Do not waste tokens on repeated `nix develop -c`, redundant research or unbounded agent loops.
- Work from the current main revision. Run targeted tests/evaluations first; CI green is not host activation. Do not independently switch/boot/reboot, rotate secrets, prune roots, migrate live data, publish services, merge PRs or assume that the current VM matches the source.
- Dreaming means **reconcile, correct, merge and link**, never just append new prose. Source → tests → dated runtime evidence; see [schema](docs/schema.md).
