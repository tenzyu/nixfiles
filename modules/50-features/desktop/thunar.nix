{
  flake.modules.nixos.thunar = {config, lib, ...}: {
    config = lib.mkIf config.local.features.thunar.enable {
      # Use the stock GTK3 Wayland-capable file manager and its native
      # D-Bus activation. No XFCE session, daemon autostart or plugins.
      programs.thunar.enable = true;
      services.gvfs.enable = true;
      xdg.mime.enable = true;
      xdg.menus.enable = true;
    };
  };

  flake.modules.homeManager.thunar = {config, lib, ...}: {
    config = lib.mkIf config.local.features.thunar.enable {
      xdg.mimeApps = {
        enable = true;
        defaultApplications."inode/directory" = ["thunar.desktop"];
      };
    };
  };
}
