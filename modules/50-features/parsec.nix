{
  flake.local.featurePolicies.parsec.unfree = [
    "parsec-bin"
  ];

  flake.features.parsec.contributions.homeManager.hyprland-tenzyu = {
    when.sameBoundary.features = [
      "parsec"
      "hyprland-tenzyu"
    ];

    payload = {...}: {
      wayland.windowManager.hyprland.settings.window_rule = [
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          immediate = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          fullscreen = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          stay_focused = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          no_initial_focus = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          allows_input = true;
        }
        {
          match = {
            title = "^(Parsec)$";
            xwayland = true;
          };
          focus_on_activate = true;
        }
      ];
    };
  };

  flake.modules.nixos.parsec = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.parsec.enable {};
  };

  flake.modules.homeManager.parsec = {
    config,
    lib,
    pkgs,
    ...
  }: let
    parsecPackage = pkgs.unstable.parsec-bin;

    parsecConfig = ''
      decoder_software=0
      client_decoder_h265=1
      client_vsync=0
      client_overlay_warnings=1
    '';

    parsecTouchpadGpmapId = "06cb,83d7";
    parsecTouchpadGpmapLine = "${parsecTouchpadGpmapId} a:_00 b:_00 x:_00 y:_00 bk:_00 g:_00 s:_00 sl:_00 sr:_00 l:_00 r:_00 du:_00 dr:_00 dd:_00 dl:_00 lyu:_00 lxr:_00 lyd:_00 lxl:_00 ryu:_00 rxr:_00 ryd:_00 rxl:_00 tl:_00 tr:_00";
  in {
    config = lib.mkIf config.local.features.parsec.enable {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "parsec-xwayland";
          runtimeInputs = [parsecPackage];
          text = ''
            set -euo pipefail

            parsec_exe=""
            for candidate in \
              "${parsecPackage}/bin/parsecd" \
              "${parsecPackage}/bin/parsec"
            do
              if [ -x "$candidate" ]; then
                parsec_exe="$candidate"
                break
              fi
            done

            if [ -z "$parsec_exe" ]; then
              echo "parsec-xwayland: executable not found in ${parsecPackage}/bin" >&2
              exit 127
            fi

            export SDL_VIDEODRIVER=x11
            export GDK_BACKEND=x11
            export QT_QPA_PLATFORM=xcb

            export SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=0
            export SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x0000/0x0000
            export SDL_JOYSTICK_HIDAPI=0

            mkdir -p "$HOME/.parsec"
            cd "$HOME/.parsec"

            exec "$parsec_exe" "$@"
          '';
        })
      ];

      home.activation.parsecConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        parsec_dir="$HOME/.parsec"
        parsec_config="$parsec_dir/config.txt"

        mkdir -p "$parsec_dir"

        if [ -L "$parsec_config" ]; then
          rm -f "$parsec_config"
        fi

        printf '%s' ${lib.escapeShellArg parsecConfig} > "$parsec_config"
        chmod 0600 "$parsec_config"
      '';

      home.activation.parsecTouchpadGpmap = lib.hm.dag.entryAfter ["writeBoundary"] ''
        parsec_dir="$HOME/.parsec"
        gpmap="$parsec_dir/gpmap.txt"
        tmp="$gpmap.tmp"

        mkdir -p "$parsec_dir"

        if [ -L "$gpmap" ]; then
          rm -f "$gpmap"
        fi

        if [ -f "$gpmap" ]; then
          grep -v '^${parsecTouchpadGpmapId} ' "$gpmap" > "$tmp" || true
        else
          : > "$tmp"
        fi

        printf '%s\n' ${lib.escapeShellArg parsecTouchpadGpmapLine} >> "$tmp"
        mv "$tmp" "$gpmap"
        chmod 0600 "$gpmap"
      '';

      xdg.desktopEntries.parsec-xwayland = {
        name = "Parsec XWayland";
        genericName = "Remote Desktop Client";
        exec = "parsec-xwayland";
        terminal = false;
        categories = [
          "Network"
          "RemoteAccess"
        ];
        comment = "Run Parsec as an XWayland client under Hyprland.";
      };
    };
  };
}
