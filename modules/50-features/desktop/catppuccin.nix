{inputs, ...}: {
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
        sources = import ../../../assets/catppuccin-materialized {
          inherit lib;
          upstream = inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system};
        };
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
        sources = import ../../../assets/catppuccin-materialized {
          inherit lib;
          upstream = inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system};
        };
      };
    };
  };
}
