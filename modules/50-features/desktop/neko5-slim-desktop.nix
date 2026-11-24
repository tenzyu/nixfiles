{
  flake.modules.nixos.neko5-slim-desktop = {
    config,
    lib,
    pkgs,
    ...
  }: let
    jay = pkgs.unstable.jay;
    terminal = pkgs.unstable.alacritty;
    session = pkgs.writeShellScriptBin "neko5-slim-session" ''
      set -eu
      if [ "$(id -u)" = 0 ] || [ ! -t 0 ] || [ -n "''${SSH_CONNECTION:-}" ] || [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
        echo "Start neko5-slim-session as the normal user from a local text VT." >&2
        exit 1
      fi
      export XDG_CURRENT_DESKTOP=jay
      export XDG_SESSION_DESKTOP=jay
      export XDG_SESSION_TYPE=wayland
      export MOZ_ENABLE_WAYLAND=1
      export QT_QPA_PLATFORM=wayland
      export NIXOS_OZONE_WL=1
      export SDL_VIDEODRIVER=wayland
      export JAY_NO_REALTIME=1
      exec ${lib.getExe jay} run
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
  in {
    config = lib.mkIf config.local.features.neko5-slim-desktop.enable {
      assertions = [
        {
          assertion = config.local.features.neko5-hardware.enable && !config.programs.hyprland.enable;
          message = "neko5-slim-desktop is an alternative neko5 session, not a second compositor.";
        }
      ];

      environment.systemPackages = [jay terminal session];
      # The pinned Jay package installs the portal descriptor but not a
      # D-Bus activation file. Do not start a portal daemon unconditionally.
      services.dbus.packages = [portalActivation];
      xdg.portal = {
        enable = true;
        extraPortals = [jay pkgs.xdg-desktop-portal-gtk];
        config.jay = {
          default = ["gtk"];
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
        on-graphics-initialized = { type = "exec", exec = ["${pkgs.dbus}/bin/dbus-update-activation-environment", "--systemd", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP"] }

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
        alt-Return = { type = "exec", exec = "${lib.getExe terminal}" }
        alt-p = { type = "exec", exec = ["rofi", "-show", "drun"] }
        alt-b = { type = "exec", exec = "firefox" }
        alt-o = { type = "exec", exec = "osu-lazer" }
        alt-h = "focus-left"
        alt-j = "focus-down"
        alt-k = "focus-up"
        alt-l = "focus-right"
        alt-shift-h = "move-left"
        alt-shift-j = "move-down"
        alt-shift-k = "move-up"
        alt-shift-l = "move-right"
        alt-d = "split-horizontal"
        alt-v = "split-vertical"
        alt-u = "toggle-fullscreen"
        alt-c = "open-control-center"
        alt-shift-c = "close"
        alt-shift-f = "toggle-floating"
        alt-q = "quit"
        alt-shift-r = "reload-config-toml"
        alt-F1 = { type = "show-workspace", name = "1" }
        alt-F2 = { type = "show-workspace", name = "2" }
        alt-F3 = { type = "show-workspace", name = "3" }
        alt-F4 = { type = "show-workspace", name = "4" }
        alt-F5 = { type = "show-workspace", name = "5" }
        alt-shift-F1 = { type = "move-to-workspace", name = "1" }
        alt-shift-F2 = { type = "move-to-workspace", name = "2" }
        alt-shift-F3 = { type = "move-to-workspace", name = "3" }
        alt-shift-F4 = { type = "move-to-workspace", name = "4" }
        alt-shift-F5 = { type = "move-to-workspace", name = "5" }
        ctrl-alt-F1 = { type = "switch-to-vt", num = 1 }
        ctrl-alt-F2 = { type = "switch-to-vt", num = 2 }
        ctrl-alt-F3 = { type = "switch-to-vt", num = 3 }
      '';
    };
  };
}
