{
  flake.modules.homeManager.steam-hyprland = {config, lib, ...}: {
    config = lib.mkIf (
      config.local.features.steam.enable
      && config.local.features.hyprland-tenzyu.enable
    ) {
      wayland.windowManager.hyprland.settings.window_rule = [
        {
          match = {
            class = "^(steam_app_.*)$";
          };
          immediate = true;
        }
        {
          match = {
            class = "^(steam_app_.*)$";
          };
          fullscreen = true;
        }
      ];
    };
  };
}
