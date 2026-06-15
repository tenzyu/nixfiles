{
  flake.modules.homeManager.hyprland-empty-xwayland = {config, lib, ...}: {
    config = lib.mkIf config.local.features.hyprland-tenzyu.enable {
      wayland.windowManager.hyprland.settings.window_rule = [
        {
          match = {
            class = "^$";
            title = "^$";
            xwayland = true;
            float = true;
            fullscreen = false;
          };
          no_focus = true;
        }
        {
          match = {
            class = "^$";
            title = "^$";
            xwayland = true;
            float = true;
            fullscreen = false;
          };
          no_follow_mouse = true;
        }
      ];
    };
  };
}
