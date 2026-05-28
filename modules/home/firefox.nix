{
  flake.modules.homeManager.firefox = {pkgs, ...}: {
    local.pkgs.useUnstable = true;

    programs.firefox = {
      enable = true;
      package = pkgs.unstable.firefox;
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
}
