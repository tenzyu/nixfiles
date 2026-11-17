# nixfiles

Personal NixOS / Home Manager configurations for three hosts, built with **flake-parts**, **import-tree**, and a separate local **feature-projection framework**. This repository is not a generic installer: hardware UUIDs, user identities and runtime dependencies are host-specific.

## Hosts

| NixOS configuration | Intended role |
| --- | --- |
| `neko5` | Laptop; Hyprland desktop, osu!lazer, remote build client |
| `neko6` | NixOS-WSL; CLI and Docker |
| `neko7` | Proxmox guest; CUDA, remote builder, development services, SplitCast consumer |

These are **source declarations**, not evidence of the generation currently booted or services currently running. See [host inventory](docs/host-state.md).

## Repository map

```text
flake.nix                         inputs, flake-parts and import-tree entry
foundations/framework/            feature registry, projection, CLI and tests (local flake)
foundations/fundamental/          formatter, system selection, static checks
modules/00-hosts/                 host declarations: neko5, neko6, neko7
modules/50-features/       NixOS and Home Manager feature implementations
assets/                    migration, GC and OpenCode resources
scripts/osu-performance/   osu! experiments and observation scripts
docs/index.md              LLM Wiki / OKF knowledge index
ROADMAP.md                 unverified work and future acceptance criteria
```

The evaluation path is `flake.nix` → `framework.flakeModules.default` + `import-tree ./foundations/fundamental` + `import-tree ./modules` → `configurations.nixos.<host>.module` → `nixosConfigurations.<host>`. Embedded Home Manager uses `useGlobalPkgs = true`. The framework also supports explicit standalone `configurations.homeManager` declarations.

## Inspect and validate

From the repository root:

```sh
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json
nix flake check --no-build
# Optional, builds a closure without activating the host:
nix build .#nixosConfigurations.neko5.config.system.build.toplevel --no-link
```

Evaluation, build, activation, boot, and runtime acceptance are **different gates**. No OS switch or reboot is performed by these inspection commands.

## How to change a feature

1. Inspect `modules/00-hosts/<host>/configuration.nix` for `local.features` (system) and `local.users.<name>.features` (Home Manager).
2. Add or update `modules/50-features/<feature>.nix`, registering `flake.modules.nixos.<feature>` or `flake.modules.homeManager.<feature>`, then enable it in the intended host. Feature names use kebab-case.
3. If required, declare per-feature package admission under `flake.local.featurePolicies.<feature>`, not as a global unfree exception.
4. Validate before separately authorizing a switch, boot, service migration or data mutation.

The `framework` flake input name and CLI commands remain stable while their sources reside in `foundations/framework/`; this is a source-layout refactor, not a change to NixOS feature names.

Framework tools are exposed as `framework-cli`, `framework-test`, `framework-invariants` and `feature-trace` flake apps. `feature-trace --feature NAME` scopes the trace; evaluated Nix option definitions take precedence over heuristic source-location hints. Use `nix run .#framework-cli -- --help` to inspect the supported interface.

## Safety boundaries

- Home Migration defaults to **check-only**: pending migration work aborts Home Manager activation before `writeBoundary`. Explicit `local.homeMigration.autoApply = true` at the Home Manager configuration layer is required for automatic file moves; the plan must be separately approved.
- `neko5` enables `home-layout`, but its host file explicitly notes buggy migration scripts. **Do not treat XDG data migration as accepted.** See [migration runbook](assets/home-layout/README.md).
- `nix-store-clean-current-system` respects Nix GC liveness; optional generation pruning still needs VM lifecycle acceptance. See [GC runbook](docs/nix-store-clean.md).
- `neko7` enables the OpenCode direnv integration, **not** the candidate Home Manager-managed OpenCode server unit. See [devShell](docs/opencode-devshells.md) and [migration](docs/opencode-neko7-migration.md).
- SplitCast is a separate pinned flake. `neko5` capture is disabled while `neko7` production role is declared; neither implies live broadcasting or deployment acceptance. See [consumer contract](docs/splitcast-consumer.md).
- osu! performance adjustments are experimental, not proven physical latency improvements. See [display](scripts/osu-performance/README-display.md) and [lab](scripts/osu-performance/README-lab.md).

## Documentation and design

The [OKF v0.2 Wiki](docs/index.md) is the agent-readable knowledge layer: architecture, host declarations, evidence, decisions, operations. The separate [roadmap](ROADMAP.md) contains future work and unverified gates. Source code wins over stale prose, but Git declarations alone never prove runtime state.

README organization was informed by the discoverability and host/module separation used in [Misterio77/nix-starter-configs](https://github.com/Misterio77/nix-starter-configs), [ryoppippi/dotfiles](https://github.com/ryoppippi/dotfiles), and [NixOS system configuration guidance](https://wiki.nixos.org/wiki/NixOS_system_configuration). These are structural references rather than implementation dependencies.
