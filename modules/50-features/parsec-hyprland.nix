{
  flake.modules.homeManager.parsec-hyprland = {config, lib, ...}: {
    config = lib.mkIf (
      config.local.features.parsec.enable
      && config.local.features.hyprland-tenzyu.enable
    ) {
      wayland.windowManager.hyprland.settings.window_rule = [
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          immediate = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          fullscreen = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          stay_focused = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          no_initial_focus = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          allows_input = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          focus_on_activate = true;
        }
      ];
    };
  };
}
