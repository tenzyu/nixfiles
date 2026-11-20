{
  flake.modules.homeManager.firefox = {
    config,
    lib,
    pkgs,
    ...
  }: let
    legacy = "${config.home.homeDirectory}/.mozilla/firefox";
    intended = "${config.xdg.configHome}/mozilla/firefox";
    held = builtins.elem "firefox" config.local.homeMigration.legacyGroups;
  in {
    config = lib.mkIf config.local.features.firefox.enable {
      local.homeMigration.paths = [
        {
          owner = "firefox";
          source = legacy;
          target = intended;
          route = config.programs.firefox.configPath;
          processes = ["*firefox*"];
        }
      ];

      # HM otherwise keeps the legacy directory with only an empty .keep file.
      # Retain the host directory if Firefox or Thunderbird requests real hosts.
      home.file.".mozilla/native-messaging-hosts".enable =
        lib.mkIf (
          config.programs.firefox.nativeMessagingHosts
          == []
          && config.mozilla.thunderbirdNativeMessagingHosts == []
        )
        false;

      xdg.mimeApps = {
        enable = lib.mkDefault true;
        defaultApplications = lib.genAttrs [
          "application/xhtml+xml"
          "text/html"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
        ] (_: lib.mkDefault ["firefox.desktop"]);
      };

      programs.firefox = {
        enable = true;
        package = pkgs.unstable.firefox;
        configPath =
          if held
          then legacy
          else intended;
        # A held browser uses its existing profile selection and settings.
        # Declare the default profile when that generation selects its target.
        profiles.default = lib.mkIf (!held) {
          extensions.force = true;
          settings = {
            "accessibility.force_disabled" = 1;
            "browser.pocket.enabled" = false;
            "browser.sessionstore.idleDelay" = 60000;
            "browser.sessionstore.interval" = 60000;
            "browser.tabs.unloadOnLowMemory" = true;
            "dom.ipc.processPriorityManager.enabled" = true;
            "extensions.pocket.enabled" = false;
            "gfx.webrender.all" = true;
            "layers.acceleration.force-enabled" = true;
            "media.ffmpeg.vaapi.enabled" = true;
            "media.hardware-video-decoding.force-enabled" = true;
            "widget.dmabuf.force-enabled" = true;
          };
        };
      };
    };
  };
}
