{
  flake.modules.nixos.passwordlessSudo = {
    security.sudo.wheelNeedsPassword = false;
  };
}
