{
  flake.modules.nixos.jay = {
    config,
    lib,
    pkgs,
    ...
  }: let
    jay = pkgs.unstable.jay;
    startJay = pkgs.writeShellScriptBin "start-jay" ''
      set -eu
      if [ "$(id -u)" = 0 ] || [ ! -t 0 ] || [ -n "''${SSH_CONNECTION:-}" ] || [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
        echo "Start Jay as a normal user from a local text VT." >&2
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
      export XCURSOR_THEME=Adwaita
      export XCURSOR_SIZE=24
      export XCURSOR_PATH=${pkgs.adwaita-icon-theme}/share/icons:/run/current-system/sw/share/icons
      ${lib.optionalString (config.i18n.inputMethod.enable && config.i18n.inputMethod.type == "fcitx5") "export QT_IM_MODULE=fcitx"}
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
    config = lib.mkIf config.local.features.jay.enable {
      environment.systemPackages = [jay startJay pkgs.adwaita-icon-theme];
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
    };
  };

  flake.modules.homeManager.jay = {
    config,
    lib,
    pkgs,
    osConfig ? null,
    ...
  }: let
    jay = pkgs.unstable.jay;
    terminal = if config.programs.alacritty.enable then config.programs.alacritty.package else pkgs.unstable.alacritty;
    hasRichclip = config.local.features.richclip.enable;
    hasTofi = config.local.features.tofi.enable;
    richclip = pkgs.unstable.callPackage ../../../assets/packages/richclip.nix {};
    hasIme = osConfig != null && osConfig.i18n.inputMethod.enable && osConfig.i18n.inputMethod.type == "fcitx5";
    ime = if hasIme then osConfig.i18n.inputMethod.package else null;
    clipboardHistory = ''
      selection="$(${lib.getExe pkgs.cliphist} list | rofi -dmenu -replace -i)" || exit 0
      [ -n "$selection" ] || exit 0
      printf '%s\n' "$selection" | ${lib.getExe pkgs.cliphist} decode | ${lib.getExe jay} run-privileged ${lib.getExe' pkgs.wl-clipboard "wl-copy"}
    '';
    screenshotArea = ''
      geometry="$(${lib.getExe pkgs.slurp})" || exit 0
      [ -n "$geometry" ] || exit 0
      ${lib.getExe pkgs.grim} -g "$geometry" - | ${lib.getExe' pkgs.wl-clipboard "wl-copy"} --type image/png
    '';
    # Native named actions; no resident helper or additional IPC.
    workspaceActions = lib.concatMapStringsSep "\n" (n: let
      name = toString n;
      next = toString (if n == 10 then 1 else n + 1);
      prev = toString (if n == 1 then 10 else n - 1);
    in ''
      workspace-${name} = [
        { type = "show-workspace", name = "${name}" },
        { type = "define-action", name = "next-workspace", action = "$workspace-${next}" },
        { type = "define-action", name = "previous-workspace", action = "$workspace-${prev}" },
      ]
    '') (lib.range 1 10);
    workspaceBindings = lib.concatMapStringsSep "\n" (n: let
      name = toString n;
      key = if n == 10 then "0" else name;
    in ''
      logo-${key} = "$workspace-${name}"
      logo-shift-${key} = [{ type = "move-to-workspace", name = "${name}" }, "$workspace-${name}"]
    '') (lib.range 1 10);
  in {
    config = lib.mkIf config.local.features.jay.enable {
      home.packages = [pkgs.grim pkgs.slurp pkgs.wl-clipboard pkgs.wayland-utils]
        ++ lib.optional (!config.programs.alacritty.enable) terminal
        ++ lib.optional (!hasRichclip) pkgs.cliphist;
      xdg.configFile."jay/config.toml".text = ''
          # Native Wayland desktop.
          keymap = """
              xkb_keymap {
                  xkb_keycodes { include "evdev+aliases(qwerty)" };
                  xkb_types    { include "complete"              };
                  xkb_compat   { include "complete"              };
                  xkb_symbols  { include "pc+us+inet(evdev)"     };
              };
              """

          workspace-display-order = "sorted"
          show-bar = true
          direct-scanout = true
          # Restore the known-good upstream policy; do not force async eligibility.
          tearing.mode = "variant3"
          vrr.mode = "never"
          on-graphics-initialized = [
            { type = "exec", exec = ["${pkgs.dbus}/bin/dbus-update-activation-environment", "--systemd", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP", "XCURSOR_THEME", "XCURSOR_SIZE", "XCURSOR_PATH", "QT_IM_MODULE"] },
            ${if hasRichclip then ''
              { type = "exec", exec = { prog = "${richclip}/bin/richclipd", args = [], privileged = true } },
            '' else ''
            { type = "exec", exec = { prog = "${lib.getExe' pkgs.wl-clipboard "wl-paste"}", args = ["--type", "text", "--watch", "${lib.getExe pkgs.cliphist}", "store"], privileged = true } },
            { type = "exec", exec = { prog = "${lib.getExe' pkgs.wl-clipboard "wl-paste"}", args = ["--type", "image", "--watch", "${lib.getExe pkgs.cliphist}", "store"], privileged = true } },
            ''}
            ${lib.optionalString hasIme ''
              { type = "exec", exec = { prog = "${ime}/bin/fcitx5", args = ["-r"], privileged = true } },
            ''}
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

          [actions]
          next-workspace = "$workspace-2"
          previous-workspace = "$workspace-10"
          ${workspaceActions}

          [shortcuts]
          logo-Return = { type = "exec", exec = "${lib.getExe terminal}" }
          logo-space = { type = "exec", exec = ${builtins.toJSON (if hasTofi then ["${pkgs.tofi}/bin/tofi-drun" "--drun-launch=true" "--terminal=alacritty"] else ["rofi" "-show" "drun"])} }
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
          logo-shift-v = "split-vertical"
          ${if hasRichclip then ''
            logo-v = { type = "exec", exec = ["richclip-picker"] }
          '' else ''
            logo-v = { type = "exec", exec = { shell = ${builtins.toJSON clipboardHistory} } }
          ''}
          logo-shift-s = { type = "exec", exec = { shell = ${builtins.toJSON screenshotArea}, privileged = true } }
          Print = { type = "exec", exec = { shell = "${lib.getExe pkgs.grim} - | ${lib.getExe' pkgs.wl-clipboard "wl-copy"} --type image/png", privileged = true } }
          logo-Tab = "$next-workspace"
          logo-shift-Tab = "$previous-workspace"
          logo-f = "toggle-fullscreen"
          logo-u = "toggle-fullscreen"
          logo-c = "open-control-center"
          logo-shift-c = "close"
          logo-t = "toggle-floating"
          logo-q = "close"
          logo-ctrl-shift-q = "quit"
          logo-shift-r = "reload-config-toml"
          ${lib.optionalString hasIme ''
            logo-ctrl-i = { type = "exec", exec = { prog = "${ime}/bin/fcitx5", args = ["-r"], privileged = true } }
            logo-i = { type = "exec", exec = ["${ime}/bin/fcitx5-remote", "-t"] }
          ''}
          ${workspaceBindings}
          ctrl-alt-F1 = { type = "switch-to-vt", num = 1 }
          ctrl-alt-F2 = { type = "switch-to-vt", num = 2 }
          ctrl-alt-F3 = { type = "switch-to-vt", num = 3 }
      '';
    };
  };
}
