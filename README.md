# nixfiles

Personal NixOS / Home Manager configurations for three hosts, using **flake-parts** and **import-tree**. Feature wiring is an internal repository implementation, not a separate Flake dependency. This repository is not a generic installer: hardware UUIDs, user identities and runtime dependencies are host-specific.

## Hosts

| NixOS configuration | Intended role |
| --- | --- |
| `neko5` | Laptop; Hyprland desktop, osu!lazer, remote build client |
| `neko6` | NixOS-WSL; CLI and Docker |
| `neko7` | Proxmox guest; CUDA, remote builder, development services, SplitCast consumer |

These are **source declarations**, not evidence of the generation currently booted or services currently running. See [host inventory](docs/host-state.md).

## Repository map

```text
flake.nix                        Flake inputs and two module imports
modules/_internal/configurations/ private typed configuration adapter
modules/00-hosts/                neko5, neko6, neko7 declarations
modules/10-foundations/          baseline, tooling and package overlays
modules/50-features/<domain>/    NixOS and Home Manager feature modules
modules/60-integrations/         conditional cross-feature contributions
tools/framework-cli/             separate inspection and test CLI
assets/                          migration, GC and OpenCode resources
scripts/osu-performance/         osu! experiments
docs/index.md                    LLM Wiki / OKF knowledge index
ROADMAP.md                       unfinished acceptance work
```

The evaluation path is `flake.nix` → explicit `modules/_internal/configurations/default.nix` + `import-tree ./modules` → `configurations.nixos.<host>.module` → `nixosConfigurations.<host>`. The `_internal` directory is intentionally excluded from recursive auto-import. The internal configuration adapter is **not** a Flake input. Embedded Home Manager uses `useGlobalPkgs = true`. The adapter also supports explicit standalone `configurations.homeManager` declarations.

The three host files list concrete Home Manager features. A user selection also enables a same-named NixOS feature when one is registered. neko7 selects Zsh as its login shell through the user feature list. The per-host Zsh module configures interactive Zsh on neko6, whose WSL login shell is Bash. See the [projection rules](docs/architecture.md#projection-rules).

## Inspect and validate

From the repository root:

```sh
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json
# PR-equivalent focused checks (avoid rebuilding all flake checks):
nix build --no-link .#checks.x86_64-linux.framework-cli \
  .#checks.x86_64-linux.deprecated-patterns \
  .#checks.x86_64-linux.feature-name-shape
nix run -L .#framework-test
# Optional, builds a closure without activating the host:
nix build .#nixosConfigurations.neko5.config.system.build.toplevel --no-link
```

Evaluation, build, activation, boot, and runtime acceptance are **different gates**. No OS switch or reboot is performed by these inspection commands.

## Module boundaries

- **Hosts** declare *which* features/users are selected; they do not implement a new module system.
- **Features** declare actual NixOS/Home Manager effects using native option paths and `lib.mkIf`.
- **Configuration adapter** exposes typed host and user selections to nixd and projects them into NixOS and Home Manager. A shared schema defines user and context options. The seed keeps nullable feature selections so omitted flags can use native defaults.
- **Foundations** own formatter, systems, static checks, package overlays, and CLI app exposure.
- **Tools** inspect and test configuration but do not mutate host state.

## How to change a feature

1. Inspect `modules/00-hosts/<host>/configuration.nix` for `local.features` (system) and `local.users.<name>.features` (Home Manager).
2. Add or update `modules/50-features/<domain>/<feature>.nix`, registering `flake.modules.nixos.<feature>` or `flake.modules.homeManager.<feature>`, then enable it in the intended host. Feature names use kebab-case.
3. If required, declare per-feature package admission under `flake.local.featurePolicies.<feature>`, not as a global unfree exception.
4. Validate before separately authorizing a switch, boot, service migration or data mutation.

The adapter derives feature option names from `flake.modules`. Adding a feature takes a module registration and a host selection. See the [architecture](docs/architecture.md) for how the typed seed passes those selections to NixOS and Home Manager.

Framework tools are exposed as `framework-cli`, `framework-test`, `framework-invariants` and `feature-trace` flake apps. Use `--feature NAME` with `--scope` and `--user` to select features. `--why OPTION_PATH` reports the effective NixOS value and its evaluated definitions. Feature JSON includes evaluated Nix definitions in `definitions` and scanned source locations in `source_hints`. Use `nix run .#framework-cli -- --help` to inspect the supported interface.

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
