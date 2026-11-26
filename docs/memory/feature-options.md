---
type: Reference
title: Native feature options
description: Native NixOS and Home Manager ownership and upstream option lookup.
status: stable
source_revision: 0daacae75f19dc2b01712c26471b42b2c6bc9ca3
sources:
  - id: adapter
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/_internal/configurations/configurations.nix
    title: Typed feature adapter
  - id: steam
    resource: https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/50-features/gaming/steam.nix
    title: Feature-specific package policy example
---

# Feature option ownership and upstream option lookup

This reference covers source declarations for `nixfiles` at `0daacae75f19dc2b01712c26471b42b2c6bc9ca3`. It does not describe observed host generations. **Source names and direct host selections remain stable.**

## Select the narrowest existing NixOS / Home Manager option

| Concern | Scope and authoritative native option | Local use / boundary |
| --- | --- | --- |
| System daemon or privilege | NixOS `services.*`, `users.users.*`, `security.*` | `networkmanager-access` adds only the selected user to the NM group; it must not be hidden in `networkmanager.nix` |
| Hardware access through early udev rule | NixOS `services.udev.packages` | `otd-access` ships `70-wacom-browser.rules` as a separate rule package; `services.udev.extraRules` generates a late `99-local.rules`, which is unsuitable for some `TAG+="uaccess"` matches |
| Login shell | NixOS `programs.zsh.enable`, `users.users.<name>.shell` | The existing projection from the host's selected users remains unchanged |
| Home configuration files | HM `xdg.configFile.<name>.source` | `zsh` owns `zsh/zshrc.d` relative to `xdg.configHome`, rather than using an absolute target via `home.file` |
| Application settings | HM `programs.<name>.*` | Prefer typed options over additional hand-written JSON or shell glue |
| Package exception | `flake.local.featurePolicies.<feature>` | Scope unfree / insecure exceptions to active features, not global user defaults |
| Host identity or credential | NixOS `sops.*` options and `services.tailscale.authKeyFile` | Host `sops-nix.enable` imports the provider; it does not mean a particular secret is provisioned |
| Minecraft data and systemd hardening | `services.minecraft-servers.dataDir`, `systemd.services.*.serviceConfig`, `containers.*.bindMounts` | neko7 places its world under `/srv/minecraft`; see migration evidence |
| Host SSH identity | `modules/00-hosts/<host>/` | Feature enablement must not silently copy a personal public key to every host |

## Upstream documentation checked

- [Home Manager: xdg.configFile](https://nix-community.github.io/home-manager/options/home-manager/xdg.html) and [programs.zsh](https://nix-community.github.io/home-manager/options/home-manager/programs/zsh.html): native XDG and Zsh options, including the 26.05 state-version-sensitive defaults.
- [Nixpkgs: udev module source](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/services/hardware/udev.nix) and [uaccess ordering issue](https://github.com/NixOS/nixpkgs/issues/308681): separate pre-73 rule from a generic late `extraRules` definition.
- [NixOS option search](https://search.nixos.org/options) and [Home Manager option reference](https://nix-community.github.io/home-manager/options/): search the **locked release** (NixOS / HM 26.05 here) before selecting a path or adding a new option.

## Style contract for `modules/50-features/<domain>/<feature>.nix`

A feature file owns the matching `flake.modules.nixos.<feature>` and/or
`flake.modules.homeManager.<feature>` registration. Keep one feature identity
per file where feasible; NixOS vs HM are separate module systems, but may share
the same feature name. A system account/group policy and a program's general
configuration are distinct features when independently selectable. Use
`lib.mkIf config.local.features.<name>.enable` to guard effects. Do not
introduce a separate option system for this guard. Cross-feature
contributions belong in `60-integrations`.

`otd-access` and `networkmanager-access` are **moved unchanged** to files
matching their feature names. The udev rule name/order and group membership are intentional ownership boundaries. Zsh's XDG target uses HM's native `xdg.configFile`; the NixOS account selection reuses `helpers.mapUsersWithFeature` instead of filtering users twice. These are existing source declarations, not a request for more abstraction.

## Canonical feature selection

The typed host seed accepts `null | false | true` for each feature. `null` emits no target definition; explicit `false` and `true` emit a regular-priority definition. This rule applies to NixOS, standalone Home Manager and embedded Home Manager. In embedded HM, the adapter also preserves other positive NixOS user-feature contributions without mistaking a default `false` for an explicit selection. The target NixOS or Home Manager evaluator resolves `mkDefault`, regular definitions, `mkForce`, and conflicts. The adapter does not resolve them.

For example, `steam` contributes `gaming-core.enable = lib.mkDefault true` in both system and HM modules. It is a soft default. `gaming-core = null` allows it. An explicit `false` takes precedence at regular priority. A `mkDefault true` contribution alone does not establish a hard requirement. See [ADR-0001](../adr/0001-canonical-feature-semantics.md).

## Validation and rollback

Run `nix build -L --no-link .#checks.x86_64-linux.framework`. Evaluate all three host derivations.
The focused Nix test checks presence of the XDG entry, selected NetworkManager
group membership and the early udev package's host scoping. This does **not**
prove a device was opened or an SSH/Wayland session was started.
After separate activation approval, inspect the generated `70-wacom-browser.rules` on the affected host. Confirm Firefox, terminal, and USB behavior.
A Git revert restores the original source layout and HM declaration.

`hyprland-empty-xwayland` was also registered as a standalone feature but
guarded by `hyprland-tenzyu.enable` instead of its own selection. Its own toggle did not control the feature. Its two existing XWayland rules are now a
`60-integrations/desktop` contribution to `hyprland-tenzyu`, with no rule
content changes. The former migration regression is archived; inspect the integration source and evaluated rules when changing this capability.

## Native Nix operators vs the composition helpers

- Prefer `builtins.intersectAttrs` to pick **existing** names from an attrset without mapping/filtering an entire set with `builtins.elem`. Values are supplied by the second attrset.
- Use `lib.genAttrs names (_: true)` with `builtins.hasAttr` for repeated name membership checks, where building one lazy lookup set is simpler than scanning and deduplicating a list per check.
- `namedPipeline` and `namedDisjoint` from [composition](composition.md) label plain-value transforms and reject accidental shallow collisions; they are not substitutes for `lib.mkIf`, `mkMerge` or Home Manager option definitions.
- Keep host `local.features.<name>.enable` assignments explicit. Generating those declarations obscures the selected features and makes editor navigation harder. Avoid helpers that are aliases of native Nixpkgs functions without a distinct contract.
