{
  flake.modules.nixos.hyprland-core = {pkgs, ...}: {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
      package = pkgs.unstable.hyprland;
      portalPackage = pkgs.unstable.xdg-desktop-portal-hyprland;
    };
  };

  flake.modules.homeManager.hyprland-core = {
    wayland.windowManager.hyprland = {
      enable = true;
      xwayland.enable = true;
    };
  };
}
