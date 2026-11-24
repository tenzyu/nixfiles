{
  # Physical host policy. The official osu! package is never patched.
  flake.modules.nixos.neko5-hardware = {config, lib, ...}: {
    config = lib.mkIf config.local.features.neko5-hardware.enable {
      # No OTD daemon: the official osu! process owns the in-process tablet driver.
      # Keep the two known critical HID devices out of runtime autosuspend.
      # 8089:0009 = SayoDevice O3C; 056a:037a = Wacom CTL-472.
      # Both were already 'on' in the Nov 7 snapshot; these rules prevent drift.
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="8089", ATTR{idProduct}=="0009", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="056a", ATTR{idProduct}=="037a", TEST=="power/control", ATTR{power/control}="on"
      '';

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
      # No manual RT promotion, IRQ pinning, i915 forced max freq or thermal
      # protections off. Audio RT admission remains under existing RTKit policy.
    };
  };
}
