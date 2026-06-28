{...}: {
  flake.features.passwordless-sudo.projections.nixos.payload = {...}: {
    security.sudo.wheelNeedsPassword = false;
  };
}
