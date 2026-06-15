{inputs, ...}: {
  flake.modules.nixos.catppuccin = {
    config,
    lib,
    ...
  }: {
    imports = [
      inputs.catppuccin.nixosModules.catppuccin
    ];

    config = lib.mkIf config.local.features.catppuccin.enable {
      catppuccin = {
        enable = true;
        cache.enable = true;
      };
    };
  };

  flake.modules.homeManager.catppuccin = {
    config,
    lib,
    ...
  }: {
    imports = [
      inputs.catppuccin.homeModules.catppuccin
    ];

    config = lib.mkIf config.local.features.catppuccin.enable {
      catppuccin = {
        enable = true;
        cache.enable = true;
      };
    };
  };
}
