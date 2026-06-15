{
  flake.modules.nixos.qemu-guest-agent = {
    services.qemuGuest.enable = true;
  };
}
