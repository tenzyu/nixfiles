let
  wallpaperPath = "~/Pictures/wallpaper.png";
in {
  flake.modules.homeManager.hyprpaper = {config, lib, ...}: {
    config = lib.mkIf config.local.features.hyprpaper.enable {
      services.hyprpaper = {
        enable = true;
        settings = {
          ipc = "off";
          splash = false;
          preload = [
            "${wallpaperPath}"
          ];
          wallpaper = [
            ",${wallpaperPath}"
          ];
        };
      };
    };
  };
}
