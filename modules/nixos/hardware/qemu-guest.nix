{
  flake.modules.nixos.qemuGuest = {
    services.qemuGuest.enable = true;
  };
}
