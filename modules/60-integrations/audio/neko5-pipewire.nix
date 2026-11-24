{
  flake.modules.nixos.neko5-hardware = {config, lib, ...}: {
    config = lib.mkIf (config.local.features.neko5-hardware.enable && config.local.features.pipewire.enable) {
      # Keep the established 48 kHz rate. The osu! playback quantum ceiling
      # lives in its Home Manager client config: AppImage's FHS namespace
      # does not expose the host /etc/pipewire.
      services.pipewire.extraConfig.pipewire."90-neko5-rate"."context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.allowed-rates" = [48000];
      };

      # Why: xdg-desktop-portal 1.20.4 fails PID namespace resolution
      # (fstatat ns/pid: ENOTDIR) on restarted PipeWire-Pulse. Its data-loop
      # then runs SCHED_OTHER and can miss the shared Q64 playback deadline.
      # Direct RTKit restored RR/20 and main-thread nice -11 without raising
      # privilege limits or changing quantum. Keep portal services for other
      # functions; only bypass their realtime scheduling interface here.
      services.pipewire.extraConfig.pipewire-pulse."90-neko5-rtkit"."module.rt.args" = {
        "rtportal.enabled" = false;
        "rtkit.enabled" = true;
      };

      # Only the integrated ALC257 analog PCM output. Unlike global quantum
      # forcing, this avoids changing a USB microphone's capture scheduling.
      # The operator verified 128-frame periods and a 384-frame DMA buffer
      # at 48 kHz; keep them independent of the graph quantum and BASS.
      services.pipewire.wireplumber.extraConfig."90-neko5-alc257-lowlatency" = {
        "monitor.alsa.rules" = [
          {
            matches = [{"node.name" = "~alsa_output.pci-0000_00_1f.3.*";}];
            actions = {
              "update-props" = {
                "api.alsa.period-size" = 128;
                "api.alsa.period-num" = 3;
                # Why: after RTKit repaired both client data-loops, the
                # H0 trial retained Q64 with zero observed ERR across 299
                # valid playback samples, including Discord VC and video.
                # Do not pay another 1.333 ms of nominal headroom for an
                # RT privilege failure. On recurrence, diagnose before tuning.
                "api.alsa.headroom" = 0;
                # Avoid a permanently running graph while no client is active.
                # This does not suspend the sink while osu! is playing.
                "session.suspend-timeout-seconds" = 5;
                "api.alsa.disable-tsched" = false;
              };
            };
          }
        ];
      };
    };
  };
}
