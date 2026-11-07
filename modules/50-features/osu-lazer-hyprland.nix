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
            # Identical internal/client fullscreen state to the known-good Win+F binding.
            # A static window rule may still lose a race with SDL's own fullscreen request.
            fullscreen_state = "2 0";
          }
        ];
      };
  };
}
