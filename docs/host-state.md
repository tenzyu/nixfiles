---
type: Host Inventory
title: "Host declarations"
description: "Configuration declarations versus running generation"
status: stable
source_revision: e96b8ed98dc13c9f21e76919aefdf4503f3d6c7d
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/e96b8ed98dc13c9f21e76919aefdf4503f3d6c7d/modules/00-hosts/neko5/configuration.nix
    title: "modules/00-hosts/neko5/configuration.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/e96b8ed98dc13c9f21e76919aefdf4503f3d6c7d/modules/00-hosts/neko6/configuration.nix
    title: "modules/00-hosts/neko6/configuration.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/e96b8ed98dc13c9f21e76919aefdf4503f3d6c7d/modules/00-hosts/neko7/configuration.nix
    title: "modules/00-hosts/neko7/configuration.nix"
  - id: src-4
    resource: https://github.com/tenzyu/nixfiles/blob/e96b8ed98dc13c9f21e76919aefdf4503f3d6c7d/modules/00-hosts/neko6/zsh.nix
    title: "modules/00-hosts/neko6/zsh.nix"
  - id: src-5
    resource: https://github.com/tenzyu/nixfiles/blob/e96b8ed98dc13c9f21e76919aefdf4503f3d6c7d/modules/50-features/desktop/firefox.nix
    title: "modules/50-features/desktop/firefox.nix"
---

# Host declarations versus runtime

**Scope:** the repository's Git declarations at the source revision; not a live SSH or systemd inspection.

## NixOS state compatibility

| Host | Declaration | Evidence |
| --- | --- | --- |
| neko5 | **`26.05` (operator-confirmed)** | The live host declaration was explicitly changed from `24.11` to `26.05` in [commit 52ebacf](https://github.com/tenzyu/nixfiles/commit/52ebacf8e3e29e5764d6452c00773c5d6a015f03). The operator confirmed `26.05` as the correct baseline on 2026-11-18; the [initial historical configuration](https://github.com/tenzyu/nixfiles/blob/7303643/profiles/neko5/configuration.nix) is not today's declaration. |
| neko6 | UNKNOWN, using the pinned Nixpkgs default of `26.05` | The first named WSL profile used `24.11`. SSH lookup failed, so the original imported distribution's state remains unverified. [First named WSL host](https://github.com/tenzyu/nixfiles/tree/b1c3ec0) |
| neko7 | **`26.05` (explicit source declaration)** | `local.context.systemStateVersion = "26.05"` is set in the current [host configuration](https://github.com/tenzyu/nixfiles/blob/e96b8ed98dc13c9f21e76919aefdf4503f3d6c7d/modules/00-hosts/neko7/configuration.nix). Historical records mention `25.05` and `24.11` on earlier installations, but the current filesystem's installation lineage is not independently established here; do not conflate provenance with the evaluated value. |

The evaluated NixOS state compatibility value is `26.05` on neko5 and neko7 by explicit host declaration; neko6 currently inherits the pinned Nixpkgs default, with its original WSL installation compatibility still unresolved. The user-confirmed neko5 baseline must not be silently reverted to the historical Git value. Home Manager separately declares `homeStateVersion = "26.05"` for each host's user. These are source declarations, not evidence of active generations or completed data migrations.

## neko5

The host selects laptop hardware, Intel graphics, Hyprland environment, `neko5-osu-first`, remote Nix build client, `nix-store-clean`, PipeWire and Tailscale. The user selects concrete CLI and desktop features, osu!lazer and `home-layout`. Firefox is the default browser for web links and HTML files.

- `splitcast-capture` is set to **false** in both system and user scopes.
- `home-layout` is **true**, but a host TODO says the migration scripts are buggy; safety acceptance is unresolved.
- Some features such as `waydroid`, `bluetooth`, and `docker-rootless` are set to false.
- Performance configuration does not prove physical display latency or present DSO state.

## neko6

The WSL declaration selects Docker rootful/on-boot, SSH and individual Home Manager CLI features. Zsh is enabled in Home Manager and Bash remains the login shell.

## neko7

The Proxmox declaration selects CUDA/NVIDIA, the Nix remote builder, game-server containers, `opencode-direnv`, `rtk`, the SplitCast production role and individual Home Manager CLI features. The Zsh user feature enables Zsh in NixOS and Home Manager and sets it as the login shell.

- `opencode-neko7-service` candidate source exists but is **not enabled in the host**. Whether a separately managed server is running requires runtime verification.
- `splitcast-production` is enabled in system and user scope; the consumer defines `rustCandidate = lib.mkDefault false`. Actual process state, streaming and PoC acceptance are not established by the declaration.
- `kernel-latest` is set to false.
- The [T3 runbook](t3code-neko7.md) records the later 2026-11-18 runtime observation and the separately tested on-demand Serve restore.

## Runtime acceptance

Record host, Git revision, NixOS generation, relevant `/run/current-system` store path, generated unit, process state and observation time before asserting deployment. [Architecture](architecture.md) explains why a registered feature differs from an enabled or running feature. See [OpenCode migration](opencode-neko7-migration.md) and [SplitCast consumer](splitcast-consumer.md).
