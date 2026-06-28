{...}: {
  flake.features.empty-nix-access-tokens.projections.nixos.payload = {...}: {
    nix.settings.access-tokens = [];
  };
}
