let
  wallpaperPath = "~/Pictures/wallpaper.png";
in {
  flake.modules.homeManager.hyprpaper = {
    services.hyprpaper = {
      enable = true;
      settings = {
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
