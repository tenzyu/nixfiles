{ ... }: {
  flake.effects.parsec = {
    system = {
      collect.pkgs.unfreePackages = [ "parsec-bin" ];
    };
  };

  flake.modules.homeManager.parsec =
    { lib, pkgs, ... }:
    let
      parsecPackage = pkgs.unstable.parsec-bin;

      parsecConfig = ''
        decoder_software=0
        client_decoder_h265=1
        client_vsync=0
        client_overlay_warnings=1
      '';

      # neko5 Dynabook touchpad is detected by Parsec as:
      #   HID Controller #14 (06CB/83D7)
      # Disable only this fake controller mapping. Keep real controllers possible.
      parsecTouchpadGpmapId = "06cb,83d7";
      parsecTouchpadGpmapLine = "${parsecTouchpadGpmapId} a:_00 b:_00 x:_00 y:_00 bk:_00 g:_00 s:_00 sl:_00 sr:_00 l:_00 r:_00 du:_00 dr:_00 dd:_00 dl:_00 lyu:_00 lxr:_00 lyd:_00 lxl:_00 ryu:_00 rxr:_00 ryd:_00 rxl:_00 tl:_00 tr:_00";
    in
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "parsec-xwayland";
          runtimeInputs = [ parsecPackage ];
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

            # Parsec for Linux is an X11 client. Keep it on XWayland even when
            # the rest of the Hyprland session prefers native Wayland backends.
            export SDL_VIDEODRIVER=x11
            export GDK_BACKEND=x11
            export QT_QPA_PLATFORM=xcb

            # Keep Parsec from interpreting laptop/virtual HID devices as game controllers.
            # This is narrower than hiding /dev/input and should not affect normal
            # keyboard/mouse/touchpad input delivered through XWayland.
            export SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=0
            export SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x0000/0x0000
            export SDL_JOYSTICK_HIDAPI=0

            mkdir -p "$HOME/.parsec"
            cd "$HOME/.parsec"

            exec "$parsec_exe" "$@"
          '';
        })
      ];

      # Do not use home.file here.
      #
      # Parsec writes/migrates its config at runtime. A Home Manager-managed
      # file becomes a read-only /nix/store symlink, which causes:
      #   fsutil_open: 'fopen' failed to open 'config.txt' with errno 30
      home.activation.parsecConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        parsec_dir="$HOME/.parsec"
        parsec_config="$parsec_dir/config.txt"

        mkdir -p "$parsec_dir"

        if [ -L "$parsec_config" ]; then
          rm -f "$parsec_config"
        fi

        printf '%s' ${lib.escapeShellArg parsecConfig} > "$parsec_config"
        chmod 0600 "$parsec_config"
      '';

      # Parsec can mis-detect the Dynabook touchpad as a gamepad and treat it as
      # a constantly active controller. Store an explicit all-unmapped gamepad
      # mapping for that VID/PID while preserving mappings for real controllers.
      home.activation.parsecTouchpadGpmap = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
}
