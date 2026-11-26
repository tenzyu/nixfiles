# Explicit QEMU guest capability on neko7

The former `proxmox-guest` pseudo-feature enabled both
`qemu-guest-profile` and `qemu-guest-agent` implicitly.
`qemu-guest-agent` only repeated `services.qemuGuest.enable = true`.
`qemu-guest-profile` already supplies `services.qemuGuest.enable = lib.mkDefault true`
and the Virtio initrd module lists. Both are source declarations, not
proof of guest-agent runtime operation.

NixOS already exposes the native option
[`services.qemuGuest.enable`](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/qemu-guest-agent.nix).
The host can select the profile directly without a Proxmox-specific wrapper:

```nix
configurations.nixos.neko7.module.local.features.qemu-guest-profile.enable = true;
```

The refactor removes the redundant `qemu-guest-agent` and `proxmox-guest` feature
registrations and retains the existing profile.
This reduces an implicit dependency path and removes a double definition.
Do not change `system.stateVersion`, guest network, containers, or
host activation as part of this refactor.

Acceptance requires `checks.x86_64-linux.framework` and all three NixOS
`system.build.toplevel.drvPath` evaluations to pass. The Nix test asserts
`qemu-guest-profile` is selected **only** on neko7, native
`services.qemuGuest.enable` remains true, and all expected Virtio
initrd modules are preserved. Runtime guest-agent handshake to the
Proxmox hypervisor and a boot check require separate approval.

To roll back, revert the Git commit to restore the two aliases and the prior
declarative values. Never treat a green CI as a completed VM reboot.
