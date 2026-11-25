{
  flake.modules.homeManager.osu-lazer = {config, lib, osConfig ? {}, ...}: {
    config = lib.mkIf (
      config.local.features.osu-lazer.enable
      && (osConfig.local.features.neko5-hardware.enable or false)
      && (osConfig.local.features.pipewire.enable or false)
    ) {
      # AppImage sees XDG config but not host /etc/pipewire. Preserve the
      # application's native latency request (441/44100) and constrain only
      # its playback graph's negotiated quantum, not independent capture.
      xdg.configFile = {
        # Why: portal PID namespace lookup fails (ENOTDIR) on neko5, leaving
        # the osu! data-loop SCHED_OTHER. Direct RTKit restored SCHED_RR/20
        # with unchanged Q64/441 and no extra ALSA headroom. XDG is visible
        # inside the AppImage FHS namespace, unlike host /etc/pipewire.
        # This is a client-context policy, not an osu!-only stream rule;
        # do not raise RTKit limits or promote Draw/Update/GC threads.
        "pipewire/client.conf.d/90-neko5-rtkit.conf".text = builtins.toJSON {
          "module.rt.args" = {
            "rtportal.enabled" = false;
            "rtkit.enabled" = true;
          };
        };

        "pipewire/client.conf.d/90-neko5-osu-quantum.conf".text = builtins.toJSON {
          "stream.rules" = [
            {
              matches = [{"node.name" = "alsa_playback.osu!";}];
              actions.update-props."node.max-latency" = "64/48000";
            }
          ];
        };
      };
    };
  };
}
