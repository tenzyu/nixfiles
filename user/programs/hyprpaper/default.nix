let
  wallpaperPath = "~/Pictures/wallpaper.png";
in {
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
}
