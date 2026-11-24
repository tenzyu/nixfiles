{
  flake.modules.nixos.neko5-slim-desktop = {
    config,
    lib,
    pkgs,
    ...
  }: let
    compositor = config.neko5Experiment.compositor;
    jay = pkgs.unstable.jay;
    terminal = pkgs.unstable.alacritty;
    sway = pkgs.sway;
    kwin = pkgs.kdePackages.kwin;
    accel = pkgs.kdePackages.kglobalacceld;
    weston = pkgs.weston;
    gamescope = pkgs.gamescope;
    # One launcher, selected at boot. Do not add another compositor boundary.
    launch = {
      jay = "${lib.getExe jay} run";
      sway = "${lib.getExe sway} --config ${swayConfig}";
      kwin = "${kwin}/bin/kwin_wayland --drm --no-lockscreen --no-kactivities ${kwinInit}";
      weston = "${lib.getExe weston} --backend=drm --config=${westonConfig}";
      gamescope = "${lib.getExe gamescope} --backend drm --expose-wayland --immediate-flips --prefer-output eDP-1 -W 1366 -H 768 -w 1366 -h 768 -r 60 --framerate-limit 0 -- ${gameProbe}";
    };
    desktop = if compositor == "kwin" then "KDE" else compositor;
    session = pkgs.writeShellScriptBin "neko5-slim-session" ''
      set -eu
      if [ "$(id -u)" = 0 ] || [ ! -t 0 ] || [ -n "''${SSH_CONNECTION:-}" ] || [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
        echo "Start neko5-slim-session as the normal user from a local text VT." >&2
        exit 1
      fi
      export XDG_CURRENT_DESKTOP=${desktop}
      export XDG_SESSION_DESKTOP=${desktop}
      export XDG_SESSION_TYPE=wayland
      export MOZ_ENABLE_WAYLAND=1
      export QT_QPA_PLATFORM=wayland
      export NIXOS_OZONE_WL=1
      export SDL_VIDEODRIVER=wayland
      export JAY_NO_REALTIME=1
      ${lib.optionalString (compositor == "jay") ''
        # Jay resolves server cursors before reading the TOML child environment.
        export XCURSOR_THEME=Adwaita
        export XCURSOR_SIZE=24
        export XCURSOR_PATH=${pkgs.adwaita-icon-theme}/share/icons:/run/current-system/sw/share/icons
      '' }
      echo "neko5 experiment: ${compositor}; physical 1366x768, osu! fullscreen / Limit8x; PipeWire 64/48000."
      ${lib.optionalString (compositor == "kwin") ''
        export KDE_SESSION_VERSION=6
        export KDE_FULL_SESSION=true
        ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP KDE_SESSION_VERSION KDE_FULL_SESSION
      ''}
      exec ${launch.${compositor}}
    '';
    portalActivation = pkgs.writeTextFile {
      name = "jay-portal-dbus-activation";
      destination = "/share/dbus-1/services/org.freedesktop.impl.portal.desktop.jay.service";
      text = ''
        [D-BUS Service]
        Name=org.freedesktop.impl.portal.desktop.jay
        Exec=${lib.getExe jay} portal
      '';
    };
    importEnvironment = "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd PATH WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP";
    swayConfig = pkgs.writeText "neko5-sway.conf" ''
      set $mod Mod4
      xwayland disable
      output eDP-1 mode 1366x768 scale 1 adaptive_sync off allow_tearing yes
      default_border pixel 1
      default_floating_border pixel 1
      for_window [app_id=".*"] allow_tearing yes
      bindsym $mod+Return exec ${lib.getExe terminal}
      bindsym $mod+space exec rofi -show drun
      bindsym $mod+b exec firefox
      bindsym $mod+o exec osu-lazer
      bindsym $mod+q kill
      bindsym $mod+f fullscreen toggle
      bindsym $mod+t floating toggle
      bindsym $mod+h focus left
      bindsym $mod+j focus down
      bindsym $mod+k focus up
      bindsym $mod+l focus right
      bindsym $mod+Control+Shift+q exit
      bindsym $mod+1 workspace number 1
      bindsym $mod+Shift+1 move container to workspace number 1; workspace number 1
      bindsym $mod+2 workspace number 2
      bindsym $mod+Shift+2 move container to workspace number 2; workspace number 2
      bindsym $mod+3 workspace number 3
      bindsym $mod+Shift+3 move container to workspace number 3; workspace number 3
      bindsym $mod+4 workspace number 4
      bindsym $mod+Shift+4 move container to workspace number 4; workspace number 4
      bindsym $mod+5 workspace number 5
      bindsym $mod+Shift+5 move container to workspace number 5; workspace number 5
      bindsym $mod+6 workspace number 6
      bindsym $mod+Shift+6 move container to workspace number 6; workspace number 6
      bindsym $mod+7 workspace number 7
      bindsym $mod+Shift+7 move container to workspace number 7; workspace number 7
      bindsym $mod+8 workspace number 8
      bindsym $mod+Shift+8 move container to workspace number 8; workspace number 8
      bindsym $mod+9 workspace number 9
      bindsym $mod+Shift+9 move container to workspace number 9; workspace number 9
      bindsym $mod+0 workspace number 10
      bindsym $mod+Shift+0 move container to workspace number 10; workspace number 10
      exec ${importEnvironment} SWAYSOCK
      bar {
        position top
        font pango:monospace 10
        colors {
          background #181825
          statusline #cdd6f4
        }
      }
    '';
    # Standalone KWin, not Plasma. Default config is under /etc/xdg;
    # the user's pre-existing KDE overrides, if any, must be checked in the trial.
    kwinInit = pkgs.writeShellScript "neko5-kwin-init" ''
      export QT_QPA_PLATFORM=wayland
      ${importEnvironment} QT_QPA_PLATFORM
    '';
    kwinScript = pkgs.runCommand "neko5-kwin-shortcuts" {} ''
      dir="$out/share/kwin/scripts/neko5-experiment"
      mkdir -p "$dir/contents/code"
      cat > "$dir/metadata.json" <<'EOF'
      {"KPlugin":{"Id":"neko5-experiment","Name":"neko5 experiment shortcuts","EnabledByDefault":true},"X-Plasma-API":"javascript","KPackageStructure":"KWin/Script"}
      EOF
      cp ${../../../scripts/desktop/kwin-experiment.js} "$dir/contents/code/main.js"
    '';
    kwinApps = {
      terminal = lib.getExe terminal;
      launcher = "rofi -show drun";
      firefox = "firefox";
      osu = "osu-lazer";
    };
    kwinAppServices = lib.mapAttrs' (name: command: lib.nameValuePair "neko5-kwin-${name}" {
      description = "neko5 KWin experiment: ${name}";
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.writeShellScript "neko5-kwin-${name}" "exec ${command}"}";
      };
    }) kwinApps;
    westonApp = name: command: pkgs.writeShellScript "neko5-weston-${name}" ''
      ${importEnvironment}
      exec ${command}
    '';
    westonConfig = pkgs.writeText "neko5-weston.ini" ''
      [core]
      shell=desktop
      xwayland=false
      idle-time=0
      [shell]
      binding-modifier=super
      allow-zap=false
      background-color=0xff1e1e2e
      panel-color=0xff181825
      [output]
      name=eDP-1
      mode=1366x768
      scale=1
      vrr-mode=none
      [launcher]
      displayname=Terminal
      icon=${weston}/share/weston/terminal.png
      path=${lib.getExe terminal}
      [launcher]
      displayname=osu!
      icon=${weston}/share/weston/terminal.png
      path=${westonApp "osu" "osu-lazer"}
      [launcher]
      displayname=Firefox
      icon=${weston}/share/weston/terminal.png
      path=${westonApp "firefox" "firefox"}
      [launcher]
      displayname=Applications
      icon=${weston}/share/weston/terminal.png
      path=${westonApp "applications" "rofi -show drun"}
    '';
    # This pinned Gamescope version requires server 0 even with expose-wayland.
    # Keep Xwayland for Gamescope internals, not for the game. This is a
    # presentation-only probe and cannot pass the workspace/usability gate.
    gameProbe = pkgs.writeShellScript "neko5-gamescope-osu" ''
      unset DISPLAY
      export SDL_VIDEODRIVER=wayland
      : "''${WAYLAND_DISPLAY:?Gamescope did not expose a native Wayland display}"
      exec osu-lazer
    '';
    packages = {
      jay = [jay pkgs.adwaita-icon-theme];
      sway = [sway];
      kwin = [kwin accel kwinScript pkgs.kdePackages.libkscreen];
      weston = [weston];
      gamescope = [gamescope pkgs.xwayland];
    };
  in {
    options.neko5Experiment.compositor = lib.mkOption {
      type = lib.types.enum ["jay" "sway" "kwin" "weston" "gamescope"];
      default = "jay";
      description = "Compositor for the isolated neko5 presentation experiment.";
    };

    config = lib.mkIf config.local.features.neko5-slim-desktop.enable (lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.local.features.neko5-hardware.enable && !config.programs.hyprland.enable;
            message = "neko5-slim-desktop is an alternative neko5 session, not a second compositor.";
          }
        ];

        environment.systemPackages = [terminal session pkgs.wayland-utils] ++ packages.${compositor};
        # The same graph contract for every experimental entry. Keep the
        # system-side ALSA period-size/count and HID/thermal policies unchanged.
        services.pipewire.extraConfig.pipewire."99-neko5-experiment" = {
          "context.properties" = {
            "default.clock.rate" = 48000;
            "default.clock.allowed-rates" = [48000];
            "default.clock.quantum" = 64;
            "default.clock.min-quantum" = 64;
            "default.clock.max-quantum" = 64;
          };
        };
        xdg.portal = {
          enable = true;
          extraPortals = [pkgs.xdg-desktop-portal-gtk];
          config.${desktop}.default = ["gtk"];
        };
      }
      (lib.mkIf (compositor == "jay") {
        services.dbus.packages = [portalActivation];
        xdg.portal = {
          extraPortals = [jay];
          config.jay = {
            "org.freedesktop.impl.portal.ScreenCast" = ["jay"];
            "org.freedesktop.impl.portal.RemoteDesktop" = ["jay"];
            "org.freedesktop.impl.portal.Inhibit" = ["none"];
          };
        };
        home-manager.users.tenzyu.xdg.configFile."jay/config.toml".text = ''
          # Native-only first experiment; no Xwayland process, status polling,
          # wallpaper daemon, tray bridge, or notification startup hook.
          keymap = """
              xkb_keymap {
                  xkb_keycodes { include "evdev+aliases(qwerty)" };
                  xkb_types    { include "complete"              };
                  xkb_compat   { include "complete"              };
                  xkb_symbols  { include "pc+us+inet(evdev)"     };
              };
              """

          show-bar = true
          direct-scanout = true
          # Restore the known-good upstream policy; do not force async eligibility.
          tearing.mode = "variant3"
          vrr.mode = "never"
          on-graphics-initialized = [
            { type = "exec", exec = ["${pkgs.dbus}/bin/dbus-update-activation-environment", "--systemd", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP", "XCURSOR_THEME", "XCURSOR_SIZE", "XCURSOR_PATH"] },
            { type = "exec", exec = { prog = "${config.i18n.inputMethod.package}/bin/fcitx5", args = ["-r"], tag = "neko5-fcitx5" } },
          ]

          # The normal socket supports per-client capability rules. Grant only
          # input-method (plus ordinary desktop capabilities) to this tagged IME.
          [[clients]]
          match.tag = "neko5-fcitx5"
          capabilities = ["input-method", "layer-shell", "drm-lease"]

          [[outputs]]
          match.connector = "eDP-1"
          mode = { width = 1366, height = 768 }
          scale = 1.0

          [xwayland]
          enabled = false

          [theme]
          bg-color = "#1e1e2e"
          bar-bg-color = "#181825"
          bar-status-text-color = "#cdd6f4"
          border-width = 1
          bar-height = 24
          font = "Fira Code 11"

          [shortcuts]
          logo-Return = { type = "exec", exec = "${lib.getExe terminal}" }
          logo-space = { type = "exec", exec = ["rofi", "-show", "drun"] }
          logo-b = { type = "exec", exec = "firefox" }
          logo-o = { type = "exec", exec = "osu-lazer" }
          logo-h = "focus-left"
          logo-j = "focus-down"
          logo-k = "focus-up"
          logo-l = "focus-right"
          logo-shift-h = "move-left"
          logo-shift-j = "move-down"
          logo-shift-k = "move-up"
          logo-shift-l = "move-right"
          logo-d = "split-horizontal"
          logo-v = "split-vertical"
          logo-f = "toggle-fullscreen"
          logo-u = "toggle-fullscreen"
          logo-c = "open-control-center"
          logo-shift-c = "close"
          logo-t = "toggle-floating"
          logo-q = "close"
          logo-ctrl-shift-q = "quit"
          logo-shift-r = "reload-config-toml"
          logo-ctrl-i = { type = "exec", exec = { prog = "${config.i18n.inputMethod.package}/bin/fcitx5", args = ["-r"], tag = "neko5-fcitx5" } }
          logo-1 = { type = "show-workspace", name = "1" }
          logo-shift-1 = [{ type = "move-to-workspace", name = "1" }, { type = "show-workspace", name = "1" }]
          logo-2 = { type = "show-workspace", name = "2" }
          logo-shift-2 = [{ type = "move-to-workspace", name = "2" }, { type = "show-workspace", name = "2" }]
          logo-3 = { type = "show-workspace", name = "3" }
          logo-shift-3 = [{ type = "move-to-workspace", name = "3" }, { type = "show-workspace", name = "3" }]
          logo-4 = { type = "show-workspace", name = "4" }
          logo-shift-4 = [{ type = "move-to-workspace", name = "4" }, { type = "show-workspace", name = "4" }]
          logo-5 = { type = "show-workspace", name = "5" }
          logo-shift-5 = [{ type = "move-to-workspace", name = "5" }, { type = "show-workspace", name = "5" }]
          logo-6 = { type = "show-workspace", name = "6" }
          logo-shift-6 = [{ type = "move-to-workspace", name = "6" }, { type = "show-workspace", name = "6" }]
          logo-7 = { type = "show-workspace", name = "7" }
          logo-shift-7 = [{ type = "move-to-workspace", name = "7" }, { type = "show-workspace", name = "7" }]
          logo-8 = { type = "show-workspace", name = "8" }
          logo-shift-8 = [{ type = "move-to-workspace", name = "8" }, { type = "show-workspace", name = "8" }]
          logo-9 = { type = "show-workspace", name = "9" }
          logo-shift-9 = [{ type = "move-to-workspace", name = "9" }, { type = "show-workspace", name = "9" }]
          logo-0 = { type = "show-workspace", name = "10" }
          logo-shift-0 = [{ type = "move-to-workspace", name = "10" }, { type = "show-workspace", name = "10" }]
          ctrl-alt-F1 = { type = "switch-to-vt", num = 1 }
          ctrl-alt-F2 = { type = "switch-to-vt", num = 2 }
          ctrl-alt-F3 = { type = "switch-to-vt", num = 3 }
        '';
      })
      (lib.mkIf (compositor == "sway") {
        xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-wlr];
        xdg.portal.config.sway = {
          "org.freedesktop.impl.portal.ScreenCast" = ["wlr"];
          "org.freedesktop.impl.portal.Screenshot" = ["wlr"];
          "org.freedesktop.impl.portal.Inhibit" = ["none"];
        };
      })
      (lib.mkIf (compositor == "kwin") {
        services.dbus.packages = [accel];
        environment.pathsToLink = ["/share/kwin"];
        environment.etc."xdg/kwinrc".text = ''
          [Desktops]
          Number=10
          Rows=2
          [Compositing]
          AllowTearing=true
          [Plugins]
          neko5-experimentEnabled=true
        '';
        systemd.user.services = kwinAppServices;
      })
    ]);
  };
}
