let
  wallpaperPath = "~/Pictures/wallpaper.png";
in {
  flake.modules.homeManager.hyprpaper = {
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
}
