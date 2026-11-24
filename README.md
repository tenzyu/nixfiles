# nixfiles

**One flake, three NixOS environments, explicit choices.** This is my personal, Nix-first configuration for a latency-sensitive Linux laptop, a WSL workstation and a remote Proxmox guest. It is a real infrastructure repository, not a one-command installer for somebody else's machine.

The aim is to make the important decisions visible where they belong: **hosts choose capabilities; features implement them using native NixOS and Home Manager options; integrations connect them only when needed.** A small typed configuration layer makes those choices discoverable in an editor without trading away NixOS's merge, priority or override semantics.

## Environments

| Host | Purpose | Source-selected examples |
| --- | --- | --- |
| **neko5** | Wayland laptop and low-latency osu!lazer environment | Jay, Alacritty, Tofi, cclip, tablet tooling, PipeWire, remote build client |
| **neko6** | NixOS-WSL command-line environment | Home Manager, Docker and WSL integration |
| **neko7** | Proxmox guest for remote development and workloads | Remote builder, T3 Code, CUDA, SplitCast production consumer, Minecraft |

These are **declarations**, not claims about currently running services. Minecraft is selected on neko7; SplitCast capture is disabled on neko5. Live state, secret provisioning and the booted NixOS generation require independent evidence. [Host boundaries](docs/memory/host-state.md).

## What makes the configuration work

- **A legible host boundary.** Each `modules/00-hosts/<host>/configuration.nix` lists concrete system and user features. It does not hide them behind an opaque bundle.
- **Native behavior, centralized wiring.** `flake-parts` and `import-tree` discover module registrations; the typed adapter maps host choices to the NixOS/Home Manager module systems. The modules still own the actual options.
- **Capabilities stay independently owned.** `10-foundations` supplies shared policy, `50-features` supplies opt-in implementations, and `60-integrations` holds conditional cross-feature effects. `lib/` composes ordinary values without reinventing the module system.
- **Reproducibility with operational boundaries.** `flake.lock` pins inputs; PR checks test semantics and evaluate configurations. Rebuilds, secret changes, data migrations and publication are separate operator decisions.

[Architecture and decisions](docs/memory/index.md) · [Practical recipes](docs/cookbook/index.md)

## Explore without activating anything

With Nix and flakes available, from a checkout:

```sh
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json
nix eval --raw .#nixosConfigurations.neko7.config.system.build.toplevel.drvPath
```

The final command **evaluates** a derivation path; it neither builds a system nor switches a machine. To run focused repository tests: `nix run -L .#framework-test`. See the [inspection cookbook](docs/cookbook/inspect.md) for expected results, CI checks and troubleshooting.

## Find the right part

```text
flake.nix                 flake-parts entrypoint and pinned inputs
modules/
  _internal/             typed host-to-module projection, explicitly imported
  00-hosts/              selections for neko5, neko6 and neko7
  10-foundations/        shared policy and checks
  50-features/           independently selectable NixOS/Home Manager features
  60-integrations/       conditional cross-feature behavior
lib/                      pure Nix composition primitives
tools/framework-cli/      developer-facing inspection and regression tooling
docs/cookbook/            inspection, change and recovery procedures for humans
docs/memory/              OKF knowledge for agents: why, evidence, risks, retrieval
```

Some support assets are written in Python, TypeScript or shell; **Nix-first does not mean 100% Nix source or immutable application data**. This repository consumes [SplitCast](https://github.com/tenzyu/splitcast) through a pinned flake input; product implementation and acceptance belong upstream.

## Change safely

Start at the relevant [host declaration](modules/00-hosts/). Follow a selected capability to its implementation and its native option effects. Run focused checks and inspect the evaluation diff before requesting any activation. For the complete workflow, use [Change a host](docs/cookbook/change-host.md), [CI validation](docs/cookbook/ci-validation.md), and the [operational runbooks](docs/cookbook/index.md).

**No README command deploys anything.** `nixos-rebuild test` is not read-only; it activates units. A system rollback does not revert world files, secrets or user data. Human approval is required for host actions.

## Documentation

[Cookbook](docs/cookbook/index.md) is for operating this infrastructure. The [LLM Wiki](docs/memory/index.md) is a compact, source-linked map of why choices exist, what has been verified and where to look next. [MEMORY.md](MEMORY.md) is a small retrieval entrypoint, not a copy of either collection; [ROADMAP.md](ROADMAP.md) tracks unresolved acceptance.

The writing follows a few strong precedents in the Nix ecosystem—[mitchellh/nixos-config](https://github.com/mitchellh/nixos-config), [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config), [NobbZ/nixos-config](https://github.com/NobbZ/nixos-config), and [kclejeune/system](https://github.com/kclejeune/system)—without presenting this personal environment as a generic Nix starter.
