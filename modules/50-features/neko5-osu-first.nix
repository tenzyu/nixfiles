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
                # ALC257 is expected to be an HDA non-batch sink. 64 frames had been an
                # unmeasured safety margin (1.333 ms at 48 kHz). Start with
                # the documented default; any XRUN => restore 64 immediately.
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
      # PREEMPT_DYNAMIC was confirmed on neko5's 7.3 kernel. Full kernel
      # preemption is a bounded, revertible latency candidate. It is not
      # PREEMPT_RT and does not confer FIFO scheduling on managed .NET tasks.
      boot.kernelParams = lib.mkAfter ["preempt=full"];

      # HWP active + intel_pstate performance restricts the CPU P-state range
      # to its upper boundary (kernel intel_pstate documentation). On the
      # 2026-11-07 foreground run the package reached 94-98C and throttled.
      # On neko5 only, permit dynamic P-states while keeping EPP aggressive.
      # This is a thermal/latency hypothesis, NOT a verified p99 win; compare
      # under sustained osu! gameplay and roll back if frame timing worsens.
      powerManagement.cpuFreqGovernor = lib.mkForce "powersave";
      systemd.services.neko5-hwp-epp = {
        description = "neko5: performance EPP with dynamic Intel HWP P-states";
        wantedBy = ["multi-user.target"];
        after = ["cpufreq.service"];
        serviceConfig.Type = "oneshot";
        script = ''
          for policy in /sys/devices/system/cpu/cpufreq/policy*; do
            pref="$policy/energy_performance_preference"
            if [ -w "$pref" ]; then
              printf '%s\n' performance > "$pref"
            fi
          done
        '';
      };

      # Keep thermald and Intel microcode for platform correctness/thermal
      # safety; LZ4 zram and VM tuning are not draw-path latency optimizers.
      # No FIFO/RT, IRQ pinning, i915 forced max freq or thermal protections off.
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
    drawObserve = pkgs.writeShellApplication {
      name = "osu-draw-observe";
      runtimeInputs = with pkgs; [bash coreutils jq];
      text = ''
        exec ${pkgs.bash}/bin/bash ${../../scripts/osu-performance/draw-observe.sh} "$@"
      '';
    };
  in {
    config = lib.mkIf config.local.features.neko5-osu-first.enable {
      # In Hyprland 0.57.2 this setting may switch the compositing fallback
      # to triple buffering under load; reduce queue depth for minimum age.
      # With successful Direct Scanout this branch is bypassed. This choice
      # trades compositor throughput for latency; restore true on p99 regression.
      wayland.windowManager.hyprland.settings.config.render.new_render_scheduling = lib.mkForce false;
      home.packages = [launcher drawObserve];
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
