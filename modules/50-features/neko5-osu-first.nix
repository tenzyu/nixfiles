{...}: {
  # The official upstream AppImage and bundled libraries are never patched.
  # This module only influences scheduling, device power policy, and PipeWire
  # via ordinary Linux/Wayland interfaces. It is enabled ONLY on neko5.
  flake.modules.nixos.neko5-osu-first = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.neko5-osu-first.enable {
      # No OTD daemon: the official osu! process owns the in-process tablet driver.
      # Keep the two known critical HID devices out of runtime autosuspend.
      # 8089:0009 = SayoDevice O3C; 056a:037a = Wacom CTL-472.
      # Both were already 'on' in the Nov 7 snapshot; these rules prevent drift.
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="8089", ATTR{idProduct}=="0009", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="056a", ATTR{idProduct}=="037a", TEST=="power/control", ATTR{power/control}="on"
      '';

      # Only the integrated ALC257 analog PCM output. Unlike global quantum
      # forcing, this avoids changing a USB microphone's capture scheduling.
      # 128 frames is the aggressive first candidate, independent of BASS -128.
      # Hardware/driver may reject or round this request; no improvement claimed.
      # An unsupported period may be rounded by ALSA/PipeWire.
      services.pipewire.wireplumber.extraConfig."90-neko5-alc257-lowlatency" = {
        "monitor.alsa.rules" = [
          {
            matches = [{"node.name" = "~alsa_output.pci-0000_00_1f.3.*";}];
            actions = {
              "update-props" = {
                "api.alsa.period-size" = 128;
                "api.alsa.period-num" = 3;
                "api.alsa.headroom" = 64;
                "session.suspend-timeout-seconds" = 0;
                "api.alsa.disable-tsched" = false;
              };
            };
          }
        ];
      };
      # PREEMPT_DYNAMIC was confirmed on neko5's 7.3 kernel. Full kernel
      # preemption is a bounded, revertible latency candidate. It is not
      # PREEMPT_RT and does not confer FIFO scheduling on managed .NET tasks.
      boot.kernelParams = lib.mkAfter ["preempt=full"];

      # Keep thermald, microcode, zram, and the already-selected performance
      # governor. No RT/FIFO, IRQ pinning, i915 forcewake or kernel patch.
    };
  };

  flake.modules.homeManager.neko5-osu-first = {
    config,
    lib,
    pkgs,
    ...
  }: let
    launcher = pkgs.writeShellApplication {
      name = "osu-first";
      runtimeInputs = with pkgs; [bash coreutils findutils gnugrep procps systemd python3 util-linux];
      text = ''
        export OSU_FIRST_TIMER_EXEC=${../../scripts/osu-performance/timerslack-exec.py}
        exec ${pkgs.bash}/bin/bash ${../../scripts/osu-performance/osu-first.sh} "$@"
      '';
    };
  in {
    config = lib.mkIf config.local.features.neko5-osu-first.enable {
      home.packages = [launcher];
      # Dedicated entry only. The existing osu! desktop entry remains unchanged.
      xdg.desktopEntries.osu-first = {
        name = "osu! (neko5 performance profile)";
        genericName = "Rhythm Game";
        exec = "${launcher}/bin/osu-first tournament";
        terminal = false;
        categories = ["Game"];
        comment = "Official osu!lazer with reversible process-side Linux optimisations";
      };
    };
  };
}
