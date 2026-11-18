---
type: Architecture
title: "Feature projection"
description: "NixOS and Home Manager feature resolution"
status: stable
source_revision: fbc49f2cb418c132e84fe562f79ba5076fd2b74d
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/flake.nix
    title: "flake.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/modules/_internal/configurations/configurations.nix
    title: "modules/_internal/configurations/configurations.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/modules/_internal/configurations/materializers/options.nix
    title: "modules/_internal/configurations/materializers/options.nix"
  - id: src-4
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/modules/_internal/configurations/materializers/users.nix
    title: "modules/_internal/configurations/materializers/users.nix"
  - id: src-5
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/modules/_internal/configurations/materializers/home-manager.nix
    title: "modules/_internal/configurations/materializers/home-manager.nix"
  - id: src-6
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/modules/10-foundations/_policy/materializer.nix
    title: "modules/10-foundations/_policy/materializer.nix"
  - id: src-7
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/modules/50-features/cli/zsh.nix
    title: "modules/50-features/cli/zsh.nix"
  - id: src-8
    resource: https://github.com/tenzyu/nixfiles/blob/fbc49f2cb418c132e84fe562f79ba5076fd2b74d/modules/50-features/gaming/steam.nix
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
- Enabled users receive a system account and group, projected `local.user` and `local.context` fields, and the registered Home Manager modules through `sharedModules`. Embedded Home Manager uses `useGlobalPkgs = true` and `useUserPackages = true`.
- Standalone `configurations.homeManager` uses the same Home Manager feature registrations. The three current host declarations are NixOS configurations.

Priorities on typed seed fields resolve against other seed definitions before projection. For example, a seed `mkForce` can win inside the seed, then a target `mkForce` can override the compacted value. Freeform target options and a literal `imports` list can pass through the seed. Target imports and registered feature modules evaluate against the native target `config`; a function evaluated as a seed sees the seed's `config`.

The three hosts list concrete CLI and desktop features. neko6 and neko7 use `home-manager.users.tenzyu.local.features.zsh.enable` to enable Zsh within Home Manager and keep Bash as the login shell. The hosts set `tmux.enable = false` at the same Home Manager layer, as neko5 does for `zed-editor`, so those definitions retain native priority over `mkDefault`.

## Cross-scope feature invariant

A feature selected through `local.users.<user>.features` implies the same-named NixOS feature via `mkDefault true` when a NixOS counterpart exists. The system asserts that the implied feature is enabled. For example, neko5 selects Steam in the user feature list and the adapter enables its NixOS module, which sets `programs.steam.enable`. For Zsh, the NixOS feature also assigns Zsh as the login shell to users who select it through that path.

## Package policy

Feature policy declarations are not blanket package authorization. The NixOS materializer aggregates enabled system and user feature policy into `local.nixpkgsPolicy`, then maps to `nixpkgs.config.allowUnfreePredicate` and `permittedInsecurePackages`. Standalone Home Manager has a separate materializer.

## Verification interfaces

`nix run -L .#framework-test` runs the existing unit tests, checks the editor-facing option types through `debug.options`, and evaluates fixture configurations through the actual adapter. The fixtures cover direct options, imports, priority, user projection, cross-scope assertions, package policy and standalone Home Manager. Host regressions check explicit feature selections, removed profile registrations, Steam projection, login shells and Home Manager disable priority. The type checks exercise the option tree consumed by nixd. Live Zed completion and host activation require separate observations.

See [host inventory](host-state.md), [decisions](decisions.md), and [roadmap](../ROADMAP.md).

## Feature source layout

Feature modules remain under the numbered `50-features/` tree, grouped by domain. The directory name is an ownership and navigation aid; configuration semantics come from their explicit `flake.modules.*` declarations, not directory ordering. The `50-features/bundles/` category holds the shared defaults and package collections. Conditional multi-feature contributions belong under `60-integrations/`, using the existing feature aspect rather than a separate activation switch.

`feature-trace` recursively discovers `.nix` source files under `50-features/` while skipping private `_` directories. Its text-scanned source hints are not authoritative configuration provenance; evaluated Nix option definitions are authoritative.

The previous `osu-lazer-hyprland` aspect was a no-op compatibility placeholder. Its removal does not modify the `neko5-osu-first` performance module or Hyprland's effective runtime settings.
