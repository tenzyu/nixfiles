---
type: Host Inventory
title: "Host declarations and evidence"
description: "Source selection, recorded host observations, and unresolved state"
status: stable
source_revision: 438aa02b426db0a5962dd0102f0cbb04a5191c06
sources:
  - id: neko5
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/00-hosts/neko5/configuration.nix
    title: "neko5 host declaration"
  - id: neko6
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/00-hosts/neko6/configuration.nix
    title: "neko6 host declaration"
  - id: neko7
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/00-hosts/neko7/configuration.nix
    title: "neko7 host declaration"
---

# Host declarations, not live inventory

**Source reference:** `438aa02b426d` on 2026-11-18. Git says what each host *would configure*; it does not report its presently booted generation, service health or installed secrets. Dated operator evidence belongs in an individual runbook.

| Host | Intended platform | Declared capabilities | State-version caveat |
| --- | --- | --- | --- |
| `neko5` | Laptop / Hyprland desktop | Intel graphics, osu!lazer, remote Nix builds, PipeWire, Tailscale, XDG Home Manager | `local.context.systemStateVersion = "26.05"`; source setting corroborated by a prior operator correction, not an ongoing live measurement |
| `neko6` | NixOS-WSL | Docker (rootful), CLI programs, SSH, Home Manager | Host has no explicit `local.context.systemStateVersion`; original WSL install lineage is **unknown** |
| `neko7` | Proxmox NixOS guest | NVIDIA/CUDA, distributed Nix builder, T3 Code, SplitCast production consumer, Minecraft, Tailscale | Explicit `local.context.systemStateVersion = "26.05"`; active generation must be checked separately |

Each host's `local.users.tenzyu.context.homeStateVersion` is declared as `26.05`. This is a Home Manager compatibility choice, distinct from the OS's `system.stateVersion`. Do not mechanically upgrade compatibility versions to match `nixpkgs`.

## neko5: desktop and latency work

The host selects Hyprland, Firefox, osu!lazer, `neko5-osu-first`, `nix-remote-client` and `nix-store-clean`. Both system and user `splitcast-capture` are explicitly **disabled**. `home-layout` is enabled as a feature, but its host TODO still identifies buggy migration scripts. Activation is check-only; data movement is not accepted without the independent [home migration runbook](../../assets/home-layout/README.md).

`sops-nix` is selected in the host. This only imports/configures the provider, not a decrypted credential. The reported 1280×720 fullscreen/Direct Scanout baseline is an experimental constraint, not a measured end-to-end latency result.

## neko6: WSL

The source still declares `neko6` and its NixOS-WSL integration. Its Home Manager Zsh feature configures interactive Zsh, but its system login-shell selection differs from neko5/neko7. Retiring this host or fixing its initial state-version baseline is separate work; do not infer that a source file is unused.

## neko7: server, games and agents

The current host explicitly selects:

```nix
game-ark.enable = false;
game-rust.enable = false;
game-minecraft.enable = true;
game-srv.enable = true;
game-server-tools.enable = true;
sops-nix.enable = true;
t3code-tailnet.enable = true;
splitcast-production.enable = true;
```

Thus `neko7-mc` is the only **declared** game container, with the Minecraft world root at `/srv/minecraft` and the service HOME / Tailscale identity state at `/var/lib/game-containers/minecraft`. The old `game-server-containers` aspect remains a compatibility shim, **not** a selected host feature. ARK/Rust code remains available for a later explicit choice. See [game features](../cookbook/game-server-features.md) and [storage migration](../cookbook/game-server-srv-migration.md).

The [storage migration runbook](../cookbook/game-server-srv-migration.md) records a **dated 2026-11-18 operator report** of an offline copy, player login, and generation 68 becoming the default boot entry. That is historical evidence, not continuous confirmation of current Minecraft uptime. Its destructive/copy commands must **not** be rerun against an existing `/srv` destination.

`sops-nix` is selected on neko7. [Secret provisioning](../cookbook/secrets-and-tailscale.md) requires a host decryption identity and an actual `sops.secrets` declaration; the feature toggle alone is not evidence that a Tailscale auth key was moved into SOPS. The `t3code-tailnet` systemd service is a controlled, on-demand Serve restore, not proof that the public/Tailnet route exists now. `opencode-neko7-service` remains a candidate aspect rather than a selected host feature. SplitCast `production` is a **consumer role**, not automatic broadcast acceptance.

The [compute platform runbook](../cookbook/compute-host.md) describes the Incus substrate and operator enrollment. [Existing workload migration](../cookbook/compute-workload-migration.md) describes independent release profiles for Minecraft, T3 and gated SplitCast, without changing their persistent identities. This historical inventory does not establish that the new feature has been activated.

## Obtaining live acceptance evidence

Record the host, UTC/JST timestamp, source revision, running `/run/current-system` identity, current system profile/boot entries, service status and direct functional result. Then compare with the desired configuration. Git revision, successful `nix eval`, closure build, `nixos-rebuild test`, `switch`, boot and application-level acceptance are distinct gates.

See [architecture](architecture.md), [T3 Code runbook](../cookbook/t3code-neko7.md), [decisions](decisions.md) and [roadmap](../../ROADMAP.md).
