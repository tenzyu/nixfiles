{
  flake.modules.homeManager.parsec = {
    config,
    lib,
    ...
  }: let
    match = {
      title = "^(Parsec)$";
      xwayland = true;
    };
  in {
    config =
      lib.mkIf (
        config.local.features.parsec.enable
        && config.local.features.hyprland-tenzyu.enable
      ) {
        # Keep independent ordered rules; one rule with six effects would
        # change the evaluated Home Manager list and could affect precedence.
        wayland.windowManager.hyprland.settings.window_rule =
          map (effect: {
            inherit match;
            "${effect}" = true;
          }) [
            "immediate"
            "fullscreen"
            "stay_focused"
            "no_initial_focus"
            "allows_input"
            "focus_on_activate"
          ];
      };
  };
}
