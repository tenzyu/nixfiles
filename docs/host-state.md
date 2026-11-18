---
type: Host Inventory
title: "Host declarations"
description: "Configuration declarations versus running generation"
status: stable
source_revision: 40f04e1adb2b35b0b29bbf42bc42bb85c71b6869
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/40f04e1adb2b35b0b29bbf42bc42bb85c71b6869/modules/00-hosts/neko5/configuration.nix
    title: "modules/00-hosts/neko5/configuration.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/40f04e1adb2b35b0b29bbf42bc42bb85c71b6869/modules/00-hosts/neko6/configuration.nix
    title: "modules/00-hosts/neko6/configuration.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/40f04e1adb2b35b0b29bbf42bc42bb85c71b6869/modules/00-hosts/neko7/configuration.nix
    title: "modules/00-hosts/neko7/configuration.nix"
---

# Host declarations versus runtime

**Scope:** the repository's Git declarations at the source revision; not a live SSH or systemd inspection.

## neko5

The host selects laptop hardware, Intel graphics, Hyprland environment, `neko5-osu-first`, remote Nix build client, `nix-store-clean`, PipeWire and Tailscale. The user selects concrete CLI and desktop features, osu!lazer and `home-layout`. The host explicitly disables the Home Manager tmux and Zed features.

- `splitcast-capture` is explicitly **false** in both system and user scopes.
- `home-layout` is **true**, but a host TODO says the migration scripts are buggy; safety acceptance is unresolved.
- Some features such as `waydroid`, `bluetooth`, and `docker-rootless` are explicitly false.
- Performance configuration does not prove physical display latency or present DSO state.

## neko6

The WSL declaration selects Docker rootful/on-boot, SSH and individual Home Manager CLI features. Zsh is enabled in Home Manager and Bash remains the login shell. The Home Manager tmux feature is explicitly disabled.

## neko7

The Proxmox declaration selects CUDA/NVIDIA, the Nix remote builder, game-server containers, `opencode-direnv`, `rtk`, the SplitCast production role and individual Home Manager CLI features. NixOS and Home Manager both enable Zsh. The user keeps Bash as the login shell and explicitly disables the Home Manager tmux feature.

- `opencode-neko7-service` candidate source exists but is **not enabled in the host**. Whether a separately managed server is running requires runtime verification.
- `splitcast-production` is enabled in system and user scope; the consumer defines `rustCandidate = lib.mkDefault false`. Actual process state, streaming and PoC acceptance are not established by the declaration.
- `kernel-latest = false` is explicit.
- The [T3 runbook](t3code-neko7.md) records the later 2026-11-18 runtime observation and the separately tested on-demand Serve restore.

## Runtime acceptance

Record host, Git revision, NixOS generation, relevant `/run/current-system` store path, generated unit, process state and observation time before asserting deployment. [Architecture](architecture.md) explains why a registered feature differs from an enabled or running feature. See [OpenCode migration](opencode-neko7-migration.md) and [SplitCast consumer](splitcast-consumer.md).
