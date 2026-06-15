{
  flake.modules.nixos.passwordless-sudo = {
    security.sudo.wheelNeedsPassword = false;
  };
}
