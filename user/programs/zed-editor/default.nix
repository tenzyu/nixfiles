{
  programs.zed-editor = {
    enable = true;

    extensions = [
      "nix"
    ];

    userSettings = {
      assistant = {
        default_model = {
          provider = "google";
          model = "gemini-1.5-pro";
        };
        version = "2";
      };
      vim_mode = true;
      ui_font_size = 16;
      buffer_font_size = 16;
      telemetry = {
        metrics = false;
      };
      theme = {
        mode = "system";
        dark = "Ayu Dark";
      };
    };
  };
}
