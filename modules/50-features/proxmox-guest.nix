{
  flake.features.proxmox-guest.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    local.features = {
      qemu-guest-profile.enable = true;
      qemu-guest-agent.enable = true;
    };
  };
}
