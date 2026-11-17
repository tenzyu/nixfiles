---
type: Host Inventory
title: "Host declarations"
description: "Configuration declarations versus running generation"
status: stable
source_revision: 22191670806242933bc156e4a5e0cd9ad3ea14f1
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/00-hosts/neko5/configuration.nix
    title: "modules/00-hosts/neko5/configuration.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/00-hosts/neko6/configuration.nix
    title: "modules/00-hosts/neko6/configuration.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/00-hosts/neko7/configuration.nix
    title: "modules/00-hosts/neko7/configuration.nix"
---

# Host declarations versus runtime

**Scope:** the repository's Git declarations at the source revision; not a live SSH or systemd inspection.

## neko5

The host selects laptop hardware, Intel graphics, Hyprland environment, `neko5-osu-first`, remote Nix build client, `nix-store-clean`, PipeWire and Tailscale. The user selects desktop applications, osu!lazer and `home-layout`.

- `splitcast-capture` is explicitly **false** in both system and user scopes.
- `home-layout` is **true**, but a host TODO says the migration scripts are buggy; safety acceptance is unresolved.
- Some features such as `waydroid`, `bluetooth`, and `docker-rootless` are explicitly false.
- Performance configuration does not prove physical display latency or present DSO state.

## neko6

NixOS-WSL: WSL integration, Docker rootful/on-boot, SSH and CLI/Home Manager bundles. It is a source configuration, not evidence of a running WSL instance.

## neko7

Proxmox guest, CUDA/NVIDIA, Nix remote builder, game-server containers, `opencode-direnv`, `rtk` and SplitCast production-role declarations.

- `opencode-neko7-service` candidate source exists but is **not enabled in the host**. Whether a separately managed server is running requires runtime verification.
- `splitcast-production` is enabled in system and user scope; the consumer defines `rustCandidate = lib.mkDefault false`. Actual process state, streaming and PoC acceptance are not established by the declaration.
- `kernel-latest = false` is explicit.

## Runtime acceptance

Record host, Git revision, NixOS generation, relevant `/run/current-system` store path, generated unit, process state and observation time before asserting deployment. [Architecture](architecture.md) explains why a registered feature differs from an enabled or running feature. See [OpenCode migration](opencode-neko7-migration.md) and [SplitCast consumer](splitcast-consumer.md).
