# nixfiles

**Nix-first, multi-host NixOS and Home Manager configuration**, built with [flakes](https://nix.dev/concepts/flakes), [flake-parts](https://flake.parts/), and [import-tree](https://github.com/vic/import-tree).

This is a **personal infrastructure repository, not an installer or reusable NixOS distribution**. Hosts, hardware assumptions, users, SSH trust, persistent state and deployment permissions are specific to the machines below. The goal is to keep host declarations obvious while using native NixOS/Home Manager options for their actual effects.

## Hosts

| Flake output | Source role | Notable declared capabilities |
| --- | --- | --- |
| `nixosConfigurations.neko5` | Laptop / graphical workstation | Hyprland, osu!lazer, PipeWire, remote Nix build client, Home Manager |
| `nixosConfigurations.neko6` | NixOS-WSL configuration | CLI environment, Docker, standalone host-specific WSL integration |
| `nixosConfigurations.neko7` | Proxmox NixOS guest | CUDA, remote builder, T3 Code, SplitCast production consumer, Minecraft container |

These are **Git declarations**, not a claim about which NixOS generation is booted or which services are currently running. The current neko7 source selects Minecraft with `game-srv.enable = true` (`/srv/minecraft`); ARK and Rust are disabled. Both neko5 and neko7 select the `sops-nix` provider, but that selection alone does **not** establish that a particular secret has been provisioned or decrypted. See [host declarations and evidence](docs/host-state.md).

## Design

The host interface is intentionally explicit. A host names the features it wants; feature implementations use native NixOS and Home Manager options.

```nix
# Excerpt of the host authoring style; see the actual file for all selections.
configurations.nixos.neko7.module = {
  local.features.game-minecraft.enable = true;
  local.features.game-ark.enable = false;
  local.features.game-rust.enable = false;
  local.features.game-srv.enable = true;

  local.users.tenzyu.features.t3code-neko7.enable = true;
};
```

- **Selection vs effect:** `local.features.<name>.enable` selects a registered `flake.modules.nixos` or `flake.modules.homeManager` feature. Each feature owns its own `lib.mkIf` and native option assignments.
- **Typed projection:** the private configuration adapter turns the editor-visible, nullable seed into NixOS/Home Manager definitions without replacing the native module merge/override system. A selected user feature can imply a same-named NixOS capability via `mkDefault`, with a conflict assertion.
- **Meaningful composition:** `lib/composition.nix` names ordered value transformations and checks disjoint/intentional attribute composition. It does **not** redefine `mkMerge`, overlay fixed points, or NixOS priority semantics.
- **Boundaries:** hosts select; foundations provide shared infrastructure; features implement independently selectable behavior; integrations contribute conditional cross-feature rules. Per-feature unfree allowances are collected only from selected features.

Read [architecture](docs/architecture.md), [feature-option ownership](docs/feature-options.md), and [composition contracts](docs/composition.md) for precise semantics.

## Repository layout

```text
flake.nix                       inputs and flake-parts entrypoint
flake.lock                      pinned dependency graph
modules/
  _internal/configurations/    typed seed, projection and materialization (not auto-imported)
  00-hosts/                    explicit neko5 / neko6 / neko7 declarations
  10-foundations/              checks, policies, overlays and CLI apps
  50-features/<domain>/        opt-in NixOS / Home Manager capabilities
  60-integrations/             cross-feature contributions
lib/                            pure, tested composition and selection utilities
tools/framework-cli/            feature tracing, tests and invariant inspection
assets/                          deployed assets and operational helpers
docs/index.md                    source-grounded Wiki / documentation index
MEMORY.md                        short agent retrieval index
ROADMAP.md                       unverified work and acceptance gates
```

Most behavior is declared in Nix; some bundled CLI, migration, testing and agent integration assets are TypeScript, Python or shell. **“Nix-first” does not mean 100% Nix source or zero mutable runtime state.**

## Inspect without changing a machine

From a checkout with a working Nix installation and flakes enabled:

```sh
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json

# Focused repository test suite; no OS activation:
nix run -L .#framework-test

# Evaluate one system derivation path, without building or activating it:
nix eval --raw .#nixosConfigurations.neko7.config.system.build.toplevel.drvPath

# Discover supported inspection commands:
nix run .#framework-cli -- --help
```

For the CI-equivalent, targeted check set, use [PR validation](docs/ci-validation.md). Avoid casually running full `nix flake check`: it can select expensive, unrelated builds. Building a system closure is also distinct from evaluating its derivation.

`feature-trace` can inspect a selected feature, and `framework-cli --why OPTION_PATH` exposes evaluated NixOS option values and definition locations. Textual source hints are **navigation aids**, not proof that a definition was selected.

## Change a host or feature

1. Locate the relevant `modules/00-hosts/<host>/configuration.nix`. Preserve its `configurations.nixos.<host>.module` and `local.users.<name>.features` authoring API; keep feature selections explicit.
2. For new behavior, register the corresponding `flake.modules.nixos.<name>` and/or `flake.modules.homeManager.<name>` under `modules/50-features/<domain>/`. Use native target options and a feature guard; cross-feature effects belong under `60-integrations/`.
3. Keep package admission under `flake.local.featurePolicies.<name>`, not a host-wide unfree bypass. Check the locked nixpkgs/Home Manager options before inventing glue.
4. Run focused tests, evaluate affected hosts, compare the resulting options and derivations, and review any state migration or restart. **A successful CI check is not permission to activate.**

**Operator-only activation:** after independent review and explicit approval on the intended host, use the relevant `nixos-rebuild test --flake .#<host>` or `switch` workflow. `test` already activates units; neither is read-only. A NixOS generation rollback does not undo writes to world data, user files, or external services.

## Operational boundaries

| Concern | Where to start |
| --- | --- |
| Current source declarations vs historical runtime observations | [Host inventory](docs/host-state.md) |
| NixOS validation and which checks CI actually runs | [CI validation](docs/ci-validation.md) |
| Secrets, age bootstrap and Tailscale identity | [Secrets and Tailscale](docs/secrets-and-tailscale.md) |
| Minecraft `/srv` cutover and historical migration steps | [Game server storage runbook](docs/game-server-srv-migration.md) |
| Home Manager XDG relocation (check-only activation) | [Home migration](assets/home-layout/README.md) |
| Nix store GC and generation rollback safety | [Nix store cleanup](docs/nix-store-clean.md) |
| T3 Code/remote development on neko7 | [T3 Code runbook](docs/t3code-neko7.md) |
| SplitCast as an external flake consumer | [SplitCast integration](docs/splitcast-consumer.md) |
| Known risks and open acceptance work | [Decisions](docs/decisions.md) · [Roadmap](ROADMAP.md) |

## Documentation

The [Wiki index](docs/index.md) is a **pull-oriented map** of architecture, decisions, source-derived facts and focused runbooks. [MEMORY.md](MEMORY.md) and [AGENTS.md](AGENTS.md) provide a small agent entrypoint, not a second source of truth. Dreaming reconciles those documents against implementation and evidence rather than adding an append-only history.

### Inspirations and upstream references

The documentation layout was informed by the host/workflow emphasis in [mitchellh/nixos-config](https://github.com/mitchellh/nixos-config), the explicit non-installer boundary in [NobbZ/nixos-config](https://github.com/NobbZ/nixos-config), the module map in [kclejeune/system](https://github.com/kclejeune/system), the verification guidance in [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config), and the concise flake-output descriptions in [fufexan/dotfiles](https://github.com/fufexan/dotfiles). They are references, **not** flake dependencies.
