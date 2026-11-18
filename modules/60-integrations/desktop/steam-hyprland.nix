{
  flake.modules.homeManager.steam = {
    config,
    lib,
    ...
  }: {
    config =
      lib.mkIf (
        config.local.features.steam.enable
        && config.local.features.hyprland-tenzyu.enable
      ) {
        wayland.windowManager.hyprland.settings.window_rule =
          map (effect: {
            match.class = "^(steam_app_.*)$";
            "${effect}" = true;
          }) [
            "immediate"
            "fullscreen"
          ];
      };
  };
}
