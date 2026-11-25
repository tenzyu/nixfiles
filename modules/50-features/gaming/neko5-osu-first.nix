{...}: {
  # Optional historical Hyprland performance lab. No system policy or
  # packages from this feature are selected in the normal Jay generation.
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
        export OSU_FIRST_TIMER_EXEC=${../../../scripts/osu-performance/timerslack-exec.py}
        exec ${pkgs.bash}/bin/bash ${../../../scripts/osu-performance/osu-first.sh} "$@"
      '';
    };
    drawObserve = pkgs.writeShellApplication {
      name = "osu-draw-observe";
      runtimeInputs = with pkgs; [bash coreutils jq];
      text = ''
        exec ${pkgs.bash}/bin/bash ${../../../scripts/osu-performance/draw-observe.sh} "$@"
      '';
    };
    displayExperiment = pkgs.writeShellApplication {
      name = "osu-display";
      runtimeInputs = with pkgs; [bash coreutils jq util-linux procps];
      text = ''
        exec ${pkgs.bash}/bin/bash ${../../../scripts/osu-performance/osu-display.sh} "$@"
      '';
    };
    latencyLab = pkgs.writeShellApplication {
      name = "osu-lab";
      # Only read-only telemetry; no setcap, sudo, USB command or game injection.
      # hyprctl is already supplied by the user's Hyprland session.
      runtimeInputs = with pkgs; [python3 coreutils procps pipewire util-linux];
      text = ''
        exec ${pkgs.python3}/bin/python3 ${../../../scripts/osu-performance/osu-lab.py} "$@"
      '';
    };
  in {
    config = lib.mkIf config.local.features.neko5-osu-first.enable {
      # In Hyprland 0.57.2 this setting may switch the compositing fallback
      # to triple buffering under load; reduce queue depth for minimum age.
      # With successful Direct Scanout this branch is bypassed. This choice
      # trades compositor throughput for latency; restore true on p99 regression.
      wayland.windowManager.hyprland.settings.config.render.new_render_scheduling = lib.mkForce false;
      # Default OFF. The "name" lets a bounded CLI trial toggle the same
      # rule through `hyprctl eval`, avoiding unsupported `hyprctl setprop`.
      # Lua name/enabled are supported by Hyprland v0.57.2 upstream.
      wayland.windowManager.hyprland.settings.window_rule = lib.mkAfter [
        {
          name = "neko5-osu-display-tearing";
          enabled = false;
          match = {class = "^(osu!|osu-lazer)$";};
          immediate = true;
        }
      ];
      # Use an external child, never sleep or poll from the compositor Lua event loop.
      wayland.windowManager.hyprland.settings.bind = lib.mkAfter [
        {
          _args = [
            "SUPER + SHIFT + F11"
            (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${displayExperiment}/bin/osu-display try 12")'')
          ];
        }
        {
          _args = [
            "SUPER + CTRL + F11"
            (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${displayExperiment}/bin/osu-display on")'')
          ];
        }
        {
          _args = [
            "SUPER + SHIFT + F12"
            (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${displayExperiment}/bin/osu-display off")'')
          ];
        }
      ];
      home.packages = [launcher drawObserve displayExperiment latencyLab];
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
