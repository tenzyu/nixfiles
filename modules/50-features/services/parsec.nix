{
  flake.local.featurePolicies.parsec.unfree = [
    "parsec-bin"
  ];

  flake.modules.nixos.parsec = {};

  flake.modules.homeManager.parsec = {
    config,
    lib,
    pkgs,
    ...
  }: let
    parsecPackage = pkgs.unstable.parsec-bin.overrideAttrs (_old: {
      version = "150_104a";
      src = pkgs.unstable.fetchurl {
        url = "https://builds.parsec.app/package/parsec-linux.deb";
        hash = "sha256-yKRAdxPXLcscWfCCl36B4bno/9Z50GZogs3kyKCCHdI=";
      };
    });

    parsecSettings = {
      decoder_software = 0;
      client_decoder_h265 = 1;
      client_vsync = 0;
      client_overlay_warnings = 1;
    };

    policy = {
      directory = ".parsec";
      configFile = "config.json";
      mappingFile = "gpmap.txt";
      mappingId = "06cb,83d7";
      mode = "0600";
    };
    # The Dynabook touchpad on neko5 was reported as HID Controller #14.
    parsecTouchpadGpmapLine = "${policy.mappingId} a:_00 b:_00 x:_00 y:_00 bk:_00 g:_00 s:_00 sl:_00 sr:_00 l:_00 r:_00 du:_00 dr:_00 dd:_00 dl:_00 lyu:_00 lxr:_00 lyd:_00 lxl:_00 ryu:_00 rxr:_00 ryd:_00 rxl:_00 tl:_00 tr:_00";
    activationData = pkgs.writeText "parsec-activation.json" (builtins.toJSON {
      inherit (config.local.parsecActivation) directory configFile mappingFile mappingId mode;
      configSettings = parsecSettings;
      mappingRow = parsecTouchpadGpmapLine;
    });
    activate = ''${pkgs.python3}/bin/python3 -I ${../../../assets/parsec-activation/activate.py} ${../../../assets/safety/shell/native.py} ${activationData}'';
  in {
    options.local.parsecActivation = lib.mkOption {
      internal = true;
      readOnly = true;
      default = if config.local.features.parsec.enable then policy else null;
      type = with lib.types; nullOr (submodule {
        options = lib.mapAttrs (_: _: lib.mkOption {type = str;}) policy;
      });
      description = "User-owned Parsec activation paths relative to HOME and the declared mapping ID.";
    };

    config = lib.mkIf config.local.features.parsec.enable {
      home.packages = [
        (pkgs.writeShellScriptBin "parsec-activation-review" ''
          exec ${activate} review "$@"
        '')
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

            mkdir -p "$HOME/${policy.directory}"
            cd "$HOME/${policy.directory}"

            exec "$parsec_exe" "$@"
          '';
        })
      ];

      home.activation.parsecConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run ${activate} config
      '';

      home.activation.parsecTouchpadGpmap = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run ${activate} mapping
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
