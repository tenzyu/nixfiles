# nixfiles

This repository contains my personal Nix-first configuration for a latency-sensitive Linux laptop, a WSL workstation and a remote Proxmox guest. It is not a general-purpose installer.

Hosts select features. Features implement native NixOS and Home Manager options. Integrations define conditional interactions between features. The typed configuration layer provides editor completion and retains NixOS merge, priority and override semantics.

## Environments

| Host | Purpose | Source-selected examples |
| --- | --- | --- |
| **neko5** | Wayland laptop and low-latency osu!lazer environment | Jay, Alacritty, Rofi, cclip, tablet tooling, PipeWire, remote build client |
| **neko6** | NixOS-WSL command-line environment | Home Manager, Docker and WSL integration |
| **neko7** | Proxmox guest for remote development and workloads | Remote builder, T3 Code, CUDA, SplitCast production consumer, Minecraft |

These are **declarations**, not claims about currently running services. Minecraft is selected on neko7; SplitCast capture is disabled on neko5. Live state, secret provisioning and the booted NixOS generation require independent evidence. [Host boundaries](docs/memory/host-state.md).

## Configuration structure

- Each `modules/00-hosts/<host>/configuration.nix` lists concrete system and user features without an implicit bundle.
- `flake-parts` and `import-tree` discover module registrations. The typed adapter maps host choices to the NixOS and Home Manager module systems. The modules define the options.
- `10-foundations` contains shared policy. `50-features` contains opt-in implementations. `60-integrations` defines conditional cross-feature effects. `lib/` composes ordinary Nix values without replacing the module system.
- `flake.lock` pins inputs. Pull request checks test semantics and evaluate configurations. Rebuilds, secret changes, data migrations and publication require separate operator decisions.

[Architecture and decisions](docs/memory/index.md) · [Practical recipes](docs/cookbook/index.md)

Leave ordinary application state in HOME alone unless it causes a concrete problem. Use native NixOS/Home Manager/application options, on-demand inspection and recoverable changes rather than implementing a new global authority. The existing HOME migration engine remains on `main` until separately reviewed retirement; no host migration or permission change is implied by the [HOME maintenance ADR](docs/adr/0003-home-layout-reuse-first.md).

## Explore without activating anything

With Nix and flakes available, from a checkout:

```sh
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json
nix eval --raw .#nixosConfigurations.neko7.config.system.build.toplevel.drvPath
```

The final command **evaluates** a derivation path; it neither builds a system nor switches a machine. To run focused repository tests: `nix build -L --no-link .#checks.x86_64-linux.validation`. See the [inspection cookbook](docs/cookbook/inspect.md) for expected results, CI checks and troubleshooting.

## Find the right part

```text
flake.nix                 flake-parts entrypoint and pinned inputs
modules/
  _internal/             typed host-to-module projection, explicitly imported
  00-hosts/              selections for neko5, neko6 and neko7
  10-foundations/        shared policy and checks
  40-workloads/          independent NixOS workload release definitions
  50-features/           independently selectable NixOS/Home Manager features
  60-integrations/       conditional cross-feature behavior
lib/                      pure Nix composition functions
docs/cookbook/            inspection, change and recovery procedures for humans
docs/memory/              current decisions, architecture and evidence boundaries
  archive/                immutable links to historical evidence
```

Support assets also use Python, TypeScript and shell. Applications retain mutable data. This repository consumes [SplitCast](https://github.com/tenzyu/splitcast) through a pinned flake input; product implementation and acceptance belong upstream.

## Compute host operations

[Instance operations](docs/cookbook/compute-instances.md) is the short entrypoint. On neko7, `just`, `just images`, and `just instances` discover the native task menu, buildable workload releases and live Incus inventory; container operations require operator approval. The image artifacts are build-only; VM admission and durable lifecycle are deferred. New guest releases do not require editing the host declaration or a CI matrix.

## Change safely

Start at the relevant [host declaration](modules/00-hosts/). Follow a selected capability to its implementation and its native option effects. Run focused checks and inspect the evaluation diff before requesting any activation. For the complete workflow, use [Change a host](docs/cookbook/change-host.md), [CI validation](docs/cookbook/ci-validation.md), and the [operational runbooks](docs/cookbook/index.md).

**No README command deploys anything.** `nixos-rebuild test` is not read-only; it activates units. A system rollback does not revert world files, secrets or user data. Human approval is required for host actions.

## Documentation

[Cookbook](docs/cookbook/index.md) is for operating this infrastructure. The [LLM Wiki](docs/memory/index.md) records design decisions, verification results and source references. [MEMORY.md](MEMORY.md) is a small retrieval entrypoint, not a copy of either collection; [ROADMAP.md](ROADMAP.md) tracks unresolved acceptance.

Documentation references include [mitchellh/nixos-config](https://github.com/mitchellh/nixos-config), [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config), [NobbZ/nixos-config](https://github.com/NobbZ/nixos-config), and [kclejeune/system](https://github.com/kclejeune/system). This repository documents a personal environment.

Historical research and retired interfaces are indexed in [Archive](docs/archive/README.md), not active configuration or validation inputs.
