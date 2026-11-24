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
    gamescope = pkgs.gamescope;
    # One launcher, selected at boot. Do not add another compositor boundary.
    launch = {
      jay = "${lib.getExe jay} run";
      gamescope = "${lib.getExe gamescope} --backend drm --expose-wayland --immediate-flips --prefer-output eDP-1 -W 1366 -H 768 -w 1366 -h 768 -r 60 --framerate-limit 0 -- ${gameProbe}";
    };
    desktop = compositor;
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
        export QT_IM_MODULE=fcitx
        export XCURSOR_PATH=${pkgs.adwaita-icon-theme}/share/icons:/run/current-system/sw/share/icons
      '' }
      echo "neko5 experiment: ${compositor}; physical 1366x768, osu! fullscreen / Limit8x; PipeWire 64/48000."
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
      gamescope = [gamescope pkgs.xwayland];
    };
  in {
    options.neko5Experiment.compositor = lib.mkOption {
      type = lib.types.enum ["jay" "gamescope"];
      default = "jay";
      description = "Primary Jay desktop or standalone Gamescope presentation probe.";
    };

    config = lib.mkIf config.local.features.neko5-slim-desktop.enable (lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.local.features.neko5-hardware.enable && !config.programs.hyprland.enable;
            message = "neko5-slim-desktop requires neko5 hardware and exclusive compositor ownership.";
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
            { type = "exec", exec = ["${pkgs.dbus}/bin/dbus-update-activation-environment", "--systemd", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP", "XCURSOR_THEME", "XCURSOR_SIZE", "XCURSOR_PATH", "QT_IM_MODULE"] },
            { type = "exec", exec = { prog = "${config.i18n.inputMethod.package}/bin/fcitx5", args = ["-r"], privileged = true } },
          ]

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
          logo-ctrl-i = { type = "exec", exec = { prog = "${config.i18n.inputMethod.package}/bin/fcitx5", args = ["-r"], privileged = true } }
          logo-i = { type = "exec", exec = ["${config.i18n.inputMethod.package}/bin/fcitx5-remote", "-t"] }
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
    ]);
  };
}
