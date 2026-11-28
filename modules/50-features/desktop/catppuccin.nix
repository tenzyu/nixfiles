{inputs, ...}: let
  assets = ../../../assets/catppuccin;
  lockedSource = {
    catppuccin = inputs.catppuccin.narHash;
    nixpkgs = inputs.catppuccin.inputs.nixpkgs.narHash;
  };
  sources = pkgs:
    assert pkgs.lib.assertMsg
      (builtins.fromJSON (builtins.readFile (assets + "/source.json")) == lockedSource)
      "Catppuccin assets are stale: run bash scripts/desktop/refresh-catppuccin-assets.sh and stage assets/catppuccin with flake.lock.";
      inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system}
      // {
        firefox = assets + "/firefox";
        starship = assets + "/starship";
        palette = assets + "/palette";
      };
in {
  flake.modules.nixos.catppuccin = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      inputs.catppuccin.nixosModules.catppuccin
    ];

    config = lib.mkIf config.local.features.catppuccin.enable {
      catppuccin = {
        enable = true;
        cache.enable = true;
        sources = sources pkgs;
      };
    };
  };

  flake.modules.homeManager.catppuccin = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      inputs.catppuccin.homeModules.catppuccin
    ];

    config = lib.mkIf config.local.features.catppuccin.enable {
      catppuccin = {
        enable = true;
        cache.enable = true;
        sources = sources pkgs;
      };
    };
  };
}
