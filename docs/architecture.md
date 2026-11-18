---
type: Architecture
title: "Feature projection"
description: "NixOS and Home Manager feature resolution"
status: stable
source_revision: bbac7a249a234542e0efe66449d13212414d8a16
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/flake.nix
    title: "flake.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/modules/_internal/configurations/configurations.nix
    title: "modules/_internal/configurations/configurations.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/modules/_internal/configurations/materializers/options.nix
    title: "modules/_internal/configurations/materializers/options.nix"
  - id: src-4
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/modules/_internal/configurations/materializers/users.nix
    title: "modules/_internal/configurations/materializers/users.nix"
  - id: src-5
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/modules/_internal/configurations/materializers/home-manager.nix
    title: "modules/_internal/configurations/materializers/home-manager.nix"
  - id: src-6
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/modules/10-foundations/_policy/materializer.nix
    title: "modules/10-foundations/_policy/materializer.nix"
  - id: src-7
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/modules/50-features/cli/zsh.nix
    title: "modules/50-features/cli/zsh.nix"
  - id: src-8
    resource: https://github.com/tenzyu/nixfiles/blob/bbac7a249a234542e0efe66449d13212414d8a16/modules/50-features/gaming/steam.nix
    title: "modules/50-features/gaming/steam.nix"
---

# Architecture

## Entry and registry

`flake.nix` explicitly imports `modules/_internal/configurations/default.nix` and `import-tree ./modules` into flake-parts. The `_internal` directory is excluded by import-tree and contains no separate Flake. `modules/50-features/<domain>/*.nix` registers `flake.modules.nixos.<name>`, `flake.modules.homeManager.<name>`, optional `flake.local.featurePolicies.<name>`, and checks. Hosts in `modules/00-hosts/` contribute `configurations.nixos.<host>.module`.

```text
import-tree -> flake-parts -> flake.modules registrations
                            -> typed configurations.*.<name>.module
                            -> compacted seed + registered modules
                            -> NixOS (including embedded Home Manager) or standalone Home Manager
```

## Responsibility boundary

`default.nix` imports the flake-parts registry and exposes `debug.options`. `configurations.nix` instantiates NixOS and standalone Home Manager. `materializers/options.nix` shares the common user and context declarations between the typed seed and the target modules. Feature names in both stages come from the public `flake.modules` entries.

The typed `attrsOf` / `submodule` entries expose `local.features`, `local.users` and context fields to nixd through `debug.options`. Plain `types.deferredModule` would forward definitions to the target evaluator directly. Its `getSubOptions` in the pinned Nixpkgs exposes only `_module`, so this adapter retains the typed seed.

## Projection rules

- `local.features.<name>.enable` selects a system feature. `local.users.<user>.features.<name>.enable` selects a user feature.
- The seed drops nullable fields with value `null` and forwards explicit system `false` values. After NixOS evaluates a user's feature selection, embedded Home Manager receives only enabled user features.
- `local.context.systemStateVersion` accepts the host's verified initial NixOS compatibility version. The adapter projects it as a regular `system.stateVersion` definition. It wins over native `mkDefault`, conflicts with a different regular definition, and yields to native `mkForce`. Leaving it unset uses the Nixpkgs definition.
- For enabled users, `local.users.<user>.context` supplies the account home directory, wheel membership, and Home Manager's `local.user` fields. It also supplies the defaults for `home.homeDirectory` and `home.stateVersion`. Embedded Home Manager uses `useGlobalPkgs = true` and `useUserPackages = true` and loads the registered Home Manager modules through `sharedModules`.
- The Home Manager `nh` feature installs `nh` and sets its `NH_OS_FLAKE` session variable when `local.context.flakePath` is set.
- Standalone `configurations.homeManager` uses the same Home Manager feature registrations. The three current host declarations are NixOS configurations.

Priorities on typed seed fields resolve against other seed definitions before projection. For example, a seed `mkForce` can win inside the seed, then a target `mkForce` can override the compacted value. Freeform target options and a literal `imports` list can pass through the seed. Target imports and registered feature modules evaluate against the native target `config`; a function evaluated as a seed sees the seed's `config`.

The NixOS state compatibility version controls defaults for persistent state. Nixpkgs selection controls OS upgrades. Home Manager uses each user's independent `homeStateVersion`. [NixOS option reference](https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion)

The host feature lists include `tmux.enable = false`, and neko5 also sets `zed-editor.enable = false`. The Firefox module supplies the default web associations. The neko6 Zsh module configures interactive Zsh in Home Manager while its WSL login shell is Bash.

## Cross-scope feature invariant

A feature selected through `local.users.<user>.features` implies the same-named NixOS feature via `mkDefault true` when a NixOS counterpart exists. The system asserts that the implied feature is enabled. For example, neko5 selects Steam in the user feature list and the adapter enables its NixOS module, which sets `programs.steam.enable`. For Zsh, the NixOS feature also assigns Zsh as the login shell to users who select it through that path.

## Package policy

Feature policy declarations are not blanket package authorization. The NixOS materializer aggregates enabled system and user feature policy into `local.nixpkgsPolicy`, then maps to `nixpkgs.config.allowUnfreePredicate` and `permittedInsecurePackages`. Standalone Home Manager has a separate materializer.

## Verification interfaces

`nix run -L .#framework-test` runs the existing unit tests, checks the editor-facing option types through `debug.options`, and evaluates fixture configurations through the actual adapter. The fixtures cover direct options, imports, priority, user projection, cross-scope assertions, package policy and standalone Home Manager. Host regressions check explicit feature selections, removed profile registrations, Steam projection, login shells and the evaluated disabled features. The type checks exercise the option tree consumed by nixd. Live Zed completion and host activation require separate observations.

See [host inventory](host-state.md), [decisions](decisions.md), and [roadmap](../ROADMAP.md).

## Feature source layout

Feature modules remain under the numbered `50-features/` tree, grouped by domain. The directory name is an ownership and navigation aid; configuration semantics come from their explicit `flake.modules.*` declarations, not directory ordering. The `50-features/bundles/` category holds the shared defaults and package collections. Conditional multi-feature contributions belong under `60-integrations/`, using the existing feature aspect rather than a separate activation switch.

`feature-trace` reads the Git flake working tree and recursively discovers `.nix` source files under `50-features/` while skipping private `_` directories. Nix evaluates tracked files, including local edits. For feature traces, `definitions` contains evaluated option definitions where available, and `source_hints` contains textual matches that can guide editor navigation. Home Manager feature status comes from evaluated settings. The locations in its feature rows are source hints. `--why` reports the effective NixOS option value and reads provenance from `definitionsWithLocations`.

The previous `osu-lazer-hyprland` aspect was a no-op compatibility placeholder. Its removal does not modify the `neko5-osu-first` performance module or Hyprland's effective runtime settings.
