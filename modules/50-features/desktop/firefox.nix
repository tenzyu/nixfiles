{
  flake.modules.homeManager.firefox = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.firefox.enable {
      local.homeMigration.paths = [
        {
          source = "${config.home.homeDirectory}/.mozilla/firefox";
          target = config.programs.firefox.configPath;
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

      programs.firefox = {
        enable = true;
        package = pkgs.unstable.firefox;
        configPath = "${config.xdg.configHome}/mozilla/firefox";
        profiles.default = {
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
