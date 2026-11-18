{
  flake.modules.homeManager.hyprland-tenzyu = {
    config,
    lib,
    ...
  }: let
    match = {
      class = "^$";
      title = "^$";
      xwayland = true;
      float = true;
      fullscreen = false;
    };
  in {
    config = lib.mkIf config.local.features.hyprland-tenzyu.enable {
      # Preserve two separate rules and their order; only share the match.
      wayland.windowManager.hyprland.settings.window_rule =
        map (effect: {
          inherit match;
          "${effect}" = true;
        }) [
          "no_focus"
          "no_follow_mouse"
        ];
    };
  };
}
