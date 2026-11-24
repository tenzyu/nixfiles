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

      # GTK portal writes GSettings through dconf; without the writer service,
      # file chooser preferences fail to persist (ServiceUnknown).
      # Reads use the mapped database; the writer is D-Bus activated.
      programs.dconf.enable = true;
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
    ...
  }: let
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
    # Native HM option merge points for Jay's existing TOML sections.
    # Keep raw TOML action syntax (including heterogeneous action arrays).
    # Each integration owns its shortcut keys and startup contributions.
    options.local.jay = {
      startupActions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
      shortcuts = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
      };
      output = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            connector = lib.mkOption {type = lib.types.str;};
            width = lib.mkOption {type = lib.types.ints.positive;};
            height = lib.mkOption {type = lib.types.ints.positive;};
            scale = lib.mkOption {type = lib.types.float;};
            tearingMode = lib.mkOption {
              type = lib.types.nullOr (lib.types.enum ["never" "always" "variant1" "variant2" "variant3"]);
              default = null;
            };
          };
        });
        default = null;
      };
    };

    config = lib.mkIf config.local.features.jay.enable {
      home.packages = [pkgs.grim pkgs.slurp pkgs.wl-clipboard pkgs.wayland-utils];
      local.jay.shortcuts = {
        logo-shift-r = lib.mkDefault ''"reload-config-toml"'';
        logo-ctrl-shift-r = ''"reload-config-toml"'';
      };
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
            ${lib.concatMapStringsSep "\n" (action: "${action},") config.local.jay.startupActions}
          ]

          ${lib.optionalString (config.local.jay.output != null) (let
            output = config.local.jay.output;
          in ''
            [[outputs]]
            match.connector = ${builtins.toJSON output.connector}
            mode = { width = ${toString output.width}, height = ${toString output.height} }
            scale = ${builtins.toJSON output.scale}
            ${lib.optionalString (output.tearingMode != null) "tearing.mode = ${builtins.toJSON output.tearingMode}"}
          '')}

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
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (key: action: "${key} = ${action}") config.local.jay.shortcuts)}
          ${workspaceBindings}
          ctrl-alt-F1 = { type = "switch-to-vt", num = 1 }
          ctrl-alt-F2 = { type = "switch-to-vt", num = 2 }
          ctrl-alt-F3 = { type = "switch-to-vt", num = 3 }
      '';
    };
  };
}
