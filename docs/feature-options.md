# Feature option ownership and upstream option lookup

Scope: source declarations for `nixfiles` at `1e3a88b6007db2ac804a9a9b73fe805249ef4b06`, not observed
host generations. **Source names and direct host selections remain stable.**

## Select the narrowest existing NixOS / Home Manager option

| Concern | Scope and authoritative native option | Local use / boundary |
| --- | --- | --- |
| System daemon or privilege | NixOS `services.*`, `users.users.*`, `security.*` | `networkmanager-access` adds only the selected user to the NM group; it must not be hidden in `networkmanager.nix` |
| Hardware access through early udev rule | NixOS `services.udev.packages` | `otd-access` ships `70-wacom-browser.rules` as a separate rule package; `services.udev.extraRules` generates a late `99-local.rules`, which is unsuitable for some `TAG+="uaccess"` matches |
| Login shell | NixOS `programs.zsh.enable`, `users.users.<name>.shell` | The existing host/selected-user projection remains unchanged |
| Home configuration files | HM `xdg.configFile.<name>.source` | `zsh` owns `zsh/zshrc.d` relative to `xdg.configHome`, rather than using an absolute target via `home.file` |
| Application settings | HM `programs.<name>.*` | Prefer typed options over additional hand-written JSON or shell glue |
| Package exception | `flake.local.featurePolicies.<feature>` | Scope unfree / insecure exceptions to active features, not global user defaults |
| Host identity or credential | `modules/00-hosts/<host>/` | Feature enablement must not silently copy a personal SSH key to every host |

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
`lib.mkIf config.local.features.<name>.enable` to guard effects; avoid
turning that guard into a new bespoke option system. Cross-feature
contributions belong in `60-integrations`.

`otd-access` and `networkmanager-access` are **moved unchanged** to files
matching their feature names. The udev rule name/order and the group membership
are unchanged. Zsh now declares its existing XDG target through HM's native
`xdg.configFile`. No new daemon, credentials, session settings, or host
selection is introduced by this refactor.

## Validation and rollback

Run `nix run -L .#framework-test` and evaluate all three host derivations.
The focused Nix test checks presence of the XDG entry, selected NetworkManager
group membership and the early udev package's host scoping. This does **not**
prove a device was opened or an SSH/Wayland session was started.
On the affected host after separate activation approval, inspect the generated
`70-wacom-browser.rules` and confirm Firefox/terminal/USB behavior.
A Git revert restores the original source layout and HM declaration.

`hyprland-empty-xwayland` was also registered as a standalone feature but
guarded by `hyprland-tenzyu.enable` instead of its own selection, making the
feature toggle misleading. Its two existing XWayland rules are now a
`60-integrations/desktop` contribution to `hyprland-tenzyu`, with no rule
content changes. A host regression asserts both rules remain evaluated and
the unreachable feature name is no longer advertised by the typed registry.
