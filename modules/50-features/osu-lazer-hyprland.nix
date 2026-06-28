{
  flake.features.osu-lazer.contributions.homeManager.hyprland-tenzyu = {
    when.sameBoundary.features = [
      "osu-lazer"
      "hyprland-tenzyu"
    ];

    payload = {...}: {
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
