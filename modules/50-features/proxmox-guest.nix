{
  flake.modules.nixos.proxmox-guest = {config, lib, ...}: {
    config = lib.mkIf config.local.features.proxmox-guest.enable {
      local.features = {
        qemu-guest-profile.enable = true;
        qemu-guest-agent.enable = true;
      };
    };
  };
}
