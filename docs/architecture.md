---
type: Architecture
title: "Feature projection"
description: "NixOS and Home Manager feature resolution"
status: stable
source_revision: 22191670806242933bc156e4a5e0cd9ad3ea14f1
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/flake.nix
    title: "flake.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/framework/modules/configurations.nix
    title: "framework/modules/configurations.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/framework/modules/materializers/users.nix
    title: "framework/modules/materializers/users.nix"
  - id: src-4
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/framework/modules/materializers/home-manager.nix
    title: "framework/modules/materializers/home-manager.nix"
  - id: src-5
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/framework/modules/materializers/policy.nix
    title: "framework/modules/materializers/policy.nix"
---

# Architecture

## Entry and registry

`flake.nix` imports the local `framework.flakeModules.default` and `import-tree ./modules` into flake-parts. `modules/50-features/*.nix` registers `flake.modules.nixos.<name>`, `flake.modules.homeManager.<name>`, optional `flake.local.featurePolicies.<name>`, and checks. Hosts in `modules/00-hosts/` contribute `configurations.nixos.<host>.module`.

```text
flake.nix / import-tree
 -> framework/modules/configurations.nix
 -> typed host seed
 -> compactNixosSeedModule (null = unspecified)
 -> NixOS module set + materializers
 -> flake.nixosConfigurations.<host>
    -> Home Manager embedded users
```

The former `framework/` source directory now resides in `foundations/framework/`; `modules/10-fundamental/` moved to `foundations/fundamental/`. The flake input is still named `framework` for compatibility. Source links in this document's YAML frontmatter are pinned to an older commit and remain historical references.

## Projection rules

- `local.features.<name>.enable`: system feature selection.
- `local.users.<user>.features.<name>.enable`: user selection.
- If an enabled user feature also has a NixOS module, `userSeededNixosFeaturesModule` enables its NixOS counterpart with `mkDefault true`.
- `hmFactoryModule` projects only enabled user features, sets `local.user` and `local.context`, and uses `useGlobalPkgs = true`.
- Seed `null` values are dropped so missing declarations do not turn into explicit disables. `false` remains an explicit disable.
- Standalone `configurations.homeManager` is supported by the framework, but the current three host entries declare NixOS configurations.

## Cross-scope feature invariant

A selected Home Manager feature with a same-named NixOS module still implies the system feature via `mkDefault true`. If an explicit system override disables it, a NixOS assertion now fails instead of silently permitting inconsistent system/home feature states. This preserves current defaults while making the cross-scope dependency observable.

## Package policy

Feature policy declarations are not blanket package authorization. The NixOS materializer aggregates enabled system and user feature policy into `local.nixpkgsPolicy`, then maps to `nixpkgs.config.allowUnfreePredicate` and `permittedInsecurePackages`. Standalone Home Manager has a separate materializer.

## Verification interfaces

`foundations/framework/cli/src/main.ts` exposes `test`, `unit`, `invariants`, `trace`; flake apps are registered in `foundations/framework/modules/cli-apps.nix`. `foundations/fundamental/checks.nix` registers static checks. These are inspection of code paths, **not evidence that a check was executed** for this document update.

See [host inventory](host-state.md), [decisions](decisions.md), and [roadmap](../ROADMAP.md).
