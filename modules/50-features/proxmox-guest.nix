{
  flake.effects.proxmox-guest.requires = [
    "qemu-guest-profile"
    "qemu-guest-agent"
  ];
}
