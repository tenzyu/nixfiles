# Explicit QEMU guest capability on neko7

The former `proxmox-guest` pseudo-feature enabled both
`qemu-guest-profile` and `qemu-guest-agent` implicitly.
The latter only repeated `services.qemuGuest.enable = true`, while the
former already supplies `services.qemuGuest.enable = lib.mkDefault true`
and the Virtio initrd module lists. Both are source declarations, not
proof of guest-agent runtime operation.

NixOS already exposes the native option
[`services.qemuGuest.enable`](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/qemu-guest-agent.nix).
A Proxmox-specific wrapper is unnecessary when the host can select the
real capability explicitly without changing its authoring interface:

```nix
configurations.nixos.neko7.module.local.features.qemu-guest-profile.enable = true;
```

The redundant `qemu-guest-agent` and `proxmox-guest` feature
registrations are removed; the remaining profile is unchanged.
This reduces an implicit dependency path and removes a double definition.
Do not change `system.stateVersion`, guest network, containers, or
host activation as part of this refactor.

**Acceptance**: the normal `framework-test` and all three NixOS
`system.build.toplevel.drvPath` evaluations pass; Nix test asserts
`qemu-guest-profile` is selected **only** on neko7, native
`services.qemuGuest.enable` remains true, and all expected Virtio
initrd modules are preserved. Runtime guest-agent handshake to the
Proxmox hypervisor and a boot check require separate approval.

**Rollback**: Git revert to restore the two aliases and the prior
declarative values. Never treat a green CI as a completed VM reboot.
