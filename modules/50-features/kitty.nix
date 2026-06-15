{
  flake.modules.homeManager.kitty = {config, lib, ...}: {
    config = lib.mkIf config.local.features.kitty.enable {
      programs.kitty = {
        enable = true;

        settings = {
          font_family = "FiraCode Nerd Font";
          font_size = 11;
          bold_font = "auto";
          italic_font = "auto";
          bold_italic_font = "auto";
          remember_window_size = "no";
          initial_window_width = 950;
          initial_window_height = 500;
          cursor_blink_interval = 0;
          scrollback_lines = 10000;
          scrollbar = "never";
          scrollbar_interactive = "no";
          wheel_scroll_min_lines = 1;
          enable_audio_bell = "no";
          window_padding_width = 10;
          hide_window_decorations = "yes";
          background_opacity = "1.0";
          dynamic_background_opacity = "no";
          confirm_os_window_close = 0;
          selection_foreground = "none";
          selection_background = "none";
        };

        keybindings = {
          "ctrl+shift+f12" = "clear_terminal reset active";
          "ctrl+shift+h" = "show_scrollback";
        };
      };
    };
  };
}
