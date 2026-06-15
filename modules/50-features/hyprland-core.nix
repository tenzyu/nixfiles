{
  flake.modules.nixos.hyprland-core = {config, lib, pkgs, ...}: {
    config = lib.mkIf config.local.features.hyprland-core.enable {
      programs.hyprland = {
        enable = true;
        withUWSM = true;
        package = pkgs.unstable.hyprland;
        portalPackage = pkgs.unstable.xdg-desktop-portal-hyprland;
      };
    };
  };

  flake.modules.homeManager.hyprland-core = {config, lib, ...}: {
    config = lib.mkIf config.local.features.hyprland-core.enable {
      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;
      };
    };
  };
}
