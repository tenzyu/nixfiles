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
            match.class = "^(osu!|osu-lazer)$";
            immediate = true;
          }
        ];
      };
  };
}
