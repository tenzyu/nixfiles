{
  flake.modules.homeManager.osu-lazer-hyprland = {
    config,
    lib,
    ...
  }: {
    config =
      lib.mkIf (
        config.local.features.osu-lazer.enable
        && config.local.features.hyprland-tenzyu.enable
      ) {
        wayland.windowManager.hyprland.settings.window_rule = [
          {
            match = {
              class = "^(osu!)$";
            };
            immediate = true;
          }
          {
            match = {
              class = "^(osu!)$";
            };
            fullscreen = true;
          }
          {
            match = {
              class = "^(osu-lazer)$";
            };
            immediate = true;
          }
          {
            match = {
              class = "^(osu-lazer)$";
            };
            fullscreen = true;
          }
        ];
      };
  };
}
