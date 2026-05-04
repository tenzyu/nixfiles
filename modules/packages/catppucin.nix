{
  cross,
  inputs,
  lib,
  ...
}:
cross.module {
  name = "catppuccin";

  nixos.module = {
    imports = [
      inputs.catppuccin.nixosModules.catppuccin
    ];

    catppuccin.enable = true;
  };

  home.module = {
    imports = [
      inputs.catppuccin.homeModules.catppuccin
    ];

    catppuccin.enable = true;
  };
}
