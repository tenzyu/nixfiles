{
  flake.modules.homeManager.zedEditor = {pkgs, ...}: {
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
        telemetry.metrics = false;
      };
    };

    xdg.enable = true;

    xdg.dataFile."applications/zed-editor.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Zed
      GenericName=Text Editor
      Exec=${pkgs.zed-editor}/bin/zeditor %F
      Terminal=false
      Categories=Utility;TextEditor;Development;
      MimeType=text/plain;
      StartupNotify=true
    '';

    xdg.mimeApps = {
      enable = true;
      associations.added."text/plain" = ["zed-editor.desktop"];
    };
  };
}
