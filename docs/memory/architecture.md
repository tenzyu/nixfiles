---
type: Architecture
title: "Feature projection"
description: "NixOS and Home Manager feature resolution"
status: stable
source_revision: 0daacae75f19dc2b01712c26471b42b2c6bc9ca3
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/flake.nix
    title: "flake.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/_internal/configurations/configurations.nix
    title: "modules/_internal/configurations/configurations.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/_internal/configurations/materializers/options.nix
    title: "modules/_internal/configurations/materializers/options.nix"
  - id: src-4
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/_internal/configurations/materializers/users.nix
    title: "modules/_internal/configurations/materializers/users.nix"
  - id: src-5
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/_internal/configurations/materializers/home-manager.nix
    title: "modules/_internal/configurations/materializers/home-manager.nix"
  - id: src-6
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/10-foundations/_policy/materializer.nix
    title: "modules/10-foundations/_policy/materializer.nix"
  - id: src-7
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/50-features/cli/zsh.nix
    title: "modules/50-features/cli/zsh.nix"
  - id: src-8
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/50-features/gaming/steam.nix
    title: "modules/50-features/gaming/steam.nix"
---

# Architecture

## Entry and registry

`flake.nix` explicitly imports `modules/_internal/configurations/default.nix` and `import-tree ./modules` into flake-parts. `import-tree` excludes the `_internal` directory. The directory contains no separate flake. `modules/50-features/<domain>/*.nix` registers `flake.modules.nixos.<name>`, `flake.modules.homeManager.<name>`, optional `flake.local.featurePolicies.<name>`, and checks. Hosts in `modules/00-hosts/` contribute `configurations.nixos.<host>.module`.

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
- The seed drops nullable `null` definitions and forwards explicit `false` / `true` into NixOS and standalone Home Manager at regular priority. The adapter retains the typed host seed's user selection separately from the evaluated NixOS user feature value. Embedded Home Manager emits a definition when the host selection is non-null **or** the native NixOS user feature is effectively true. The emitted value is the native-effective bool. When the effective NixOS user feature is `false` and the host does not select it, the adapter emits no definition. Home Manager defaults then determine the value.
- `local.context.systemStateVersion` accepts the host's verified initial NixOS compatibility version. The adapter projects it as a regular `system.stateVersion` definition. It wins over native `mkDefault`, conflicts with a different regular definition, and yields to native `mkForce`. Leaving it unset uses the Nixpkgs definition.
- For enabled users, `local.users.<user>.context` supplies the account home directory, wheel membership, and Home Manager's `local.user` fields. It also supplies the defaults for `home.homeDirectory` and `home.stateVersion`. Embedded Home Manager uses `useGlobalPkgs = true` and `useUserPackages = true` and loads the registered Home Manager modules through `sharedModules`.
- The Home Manager `nh` feature installs `nh` and sets its `NH_OS_FLAKE` session variable when `local.context.flakePath` is set.
- Standalone `configurations.homeManager` uses the same Home Manager feature registrations. The three current host declarations are NixOS configurations.

Priorities on typed seed fields resolve against other seed definitions before projection. For example, a seed `mkForce` can win inside the seed, then a target `mkForce` can override the compacted value. Freeform target options and a literal `imports` list can pass through the seed. Target imports and registered feature modules evaluate against the native target `config`; a function evaluated as a seed sees the seed's `config`.

NixOS uses `system.stateVersion` to select defaults for persistent state. The Nixpkgs revision determines OS upgrades. Home Manager uses each user's independent `homeStateVersion`. [NixOS option reference](https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion)

The host feature lists include `tmux.enable = false`, and neko5 also sets `zed-editor.enable = false`. The Firefox module supplies the default web associations. The neko6 Zsh module configures interactive Zsh in Home Manager while its WSL login shell is Bash.

## Selection vs. effective feature state

Feature selection has three distinct levels: the typed host `null | false | true` authoring decision, the NixOS `local.users.<name>.features` effective `bool`, and the Home Manager `local.features` effective `bool`. The two module systems merge independently. A host explicit `false` defeats an HM `mkDefault true`, while host `null` allows that soft default. NixOS user-level `mkForce` can change the value emitted into HM, but does not transport its priority wrapper into HM. Existing external positive user-feature contributions continue to project into HM. See [ADR-0001](../adr/0001-canonical-feature-semantics.md).

## Cross-scope feature invariant

A feature selected through `local.users.<user>.features` implies the same-named NixOS feature via `mkDefault true` when a NixOS counterpart exists. The NixOS module asserts that the implied feature is enabled. For example, neko5 selects Steam in the user feature list and the adapter enables its NixOS module, which sets `programs.steam.enable`. For Zsh, the NixOS feature also assigns Zsh as the login shell to users who select it through that path.

## Package policy

Feature policy declarations are not blanket package authorization. The NixOS materializer aggregates enabled system and user feature policy into `local.nixpkgsPolicy`, then maps to `nixpkgs.config.allowUnfreePredicate` and `permittedInsecurePackages`. The unfree predicate uses a name-indexed `lib.genAttrs` set and `builtins.hasAttr`; the original scoped policy semantics remain unchanged. Standalone Home Manager has a separate materializer.

## Semantic value composition

The shared [composition library](composition.md) supplies `namedPipeline`, `namedDisjoint` and `overrideExisting` **for ordinary Nix values**. The adapter uses named stages when projecting typed seeds and explicitly checks disjoint or intentionally replaced fields when composing its input data. These functions do not introduce an alternate NixOS module evaluator.

Value transformations (`lib.pipe`), overlay fixed points (`lib.composeManyExtensions`) and option definitions (`imports`, `lib.mkMerge`, type/priority merging) have different semantics. For actual NixOS/Home Manager settings, retain native module definitions and inspect `options.<path>.definitionsWithLocations` when source provenance matters.

## Verification interfaces

`nix build -L --no-link .#checks.x86_64-linux.framework` runs native Nix tests of typed options, projection, priority, direct imports, user policy and standalone Home Manager. Host-policy checks separately cover actual NixOS configurations. Verify live nixd completion and activation separately.

See [host inventory](host-state.md), [decisions](decisions.md), and [roadmap](../../ROADMAP.md).

## Feature source layout

Feature modules remain under the numbered `50-features/` tree, grouped by domain. Directory names identify ownership and help locate modules. The explicit `flake.modules.*` declarations determine configuration semantics, independent of directory ordering. The `50-features/bundles/` category holds the shared defaults and package collections. Conditional multi-feature contributions belong under `60-integrations/`, using the existing feature aspect rather than a separate activation switch.

Use `nix eval`/`nix repl` for evaluated values and native `options.<path>.definitionsWithLocations` for surviving definitions; use `rg` for source navigation. See [inspection](../cookbook/inspect.md).

