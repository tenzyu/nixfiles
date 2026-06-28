{
  flake.features.steam.contributions.homeManager.hyprland-tenzyu = {
    when.sameBoundary.features = [
      "steam"
      "hyprland-tenzyu"
    ];

    payload = {...}: {
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
