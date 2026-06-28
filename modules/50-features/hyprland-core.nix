{
  flake.features.hyprland-core.projections.nixos.payload = {
    pkgs,
    ...
  }: {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
      package = pkgs.unstable.hyprland;
      portalPackage = pkgs.unstable.xdg-desktop-portal-hyprland;
    };
  };

  flake.features.hyprland-core.projections.homeManager.payload = {...}: {
    wayland.windowManager.hyprland = {
      enable = true;
      xwayland.enable = true;
    };
  };
}
