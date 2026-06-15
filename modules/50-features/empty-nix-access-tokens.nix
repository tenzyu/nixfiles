{
  flake.modules.nixos.empty-nix-access-tokens = {
    nix.settings.access-tokens = [];
  };
}
