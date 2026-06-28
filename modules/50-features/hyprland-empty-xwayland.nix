{
  flake.features.hyprland-empty-xwayland.contributions.homeManager.hyprland-tenzyu = {
    when.sameBoundary.features = [
      "hyprland-empty-xwayland"
      "hyprland-tenzyu"
    ];

    payload = {...}: {
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
