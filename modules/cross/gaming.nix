{config, ...}: let
  inherit (config.me) username;
in {
  local.cross.definitions.gaming = {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
      {
        policy.pkgs.allowUnfreeNames = ["steam" "steam-original" "steam-unwrapped" "steam-run"];
      }
    ];

    nixos.module = {
      lib,
      pkgs,
      ...
    }: let
      hyprGamingStart = pkgs.writeShellScript "hypr-gaming-start" ''
        set -eu

        systemctl --user stop mako.service 2>/dev/null || true
        pkill -STOP -x waybar 2>/dev/null || true

        for socket in "''${XDG_RUNTIME_DIR:-/run/user/$UID}"/hypr/*/.socket.sock; do
          [ -S "$socket" ] || continue
          sig="''${socket%/.socket.sock}"
          sig="''${sig##*/}"
          HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl --batch "\
            keyword animations:enabled false ; \
            keyword decoration:blur:enabled false ; \
            keyword decoration:shadow:enabled false ; \
            keyword decoration:rounding 0 ; \
            keyword general:gaps_in 0 ; \
            keyword general:gaps_out 0 ; \
            keyword general:allow_tearing true ; \
            keyword misc:vrr 2 ; \
            keyword render:direct_scanout true" >/dev/null 2>&1 || true
        done
      '';

      hyprGamingEnd = pkgs.writeShellScript "hypr-gaming-end" ''
        set -eu

        pkill -CONT -x waybar 2>/dev/null || true
        systemctl --user start mako.service 2>/dev/null || true
      '';
    in {
      programs.gamemode = {
        enable = true;
        enableRenice = true;
        settings = {
          general = {
            inhibit_screensaver = 0;
            renice = 10;
            softrealtime = "auto";
          };
          custom = {
            start = "${hyprGamingStart}";
            end = "${hyprGamingEnd}";
          };
        };
      };

      programs.gamescope = {
        enable = true;
        capSysNice = true;
        args = [
          "--rt"
        ];
      };

      users.users.${username}.extraGroups = lib.mkAfter [
        "gamemode"
        "video"
        "input"
      ];

      environment.systemPackages = with pkgs; [
        gamemode
        gamescope
        intel-gpu-tools
        libva-utils
        powertop
        vulkan-tools
      ];
    };

    home.module = {pkgs, ...}: {
      home.packages = [
        (pkgs.writeShellApplication {
      # これいらんかもなぁ
          name = "hypr-gaming-mode";
          runtimeInputs = with pkgs; [hyprland procps systemd];
          text = ''
            case "''${1:-}" in
              on)
                systemctl --user stop mako.service 2>/dev/null || true
                pkill -STOP -x waybar 2>/dev/null || true
                hyprctl --batch "keyword animations:enabled false ; keyword decoration:blur:enabled false ; keyword decoration:shadow:enabled false ; keyword decoration:rounding 0 ; keyword general:gaps_in 0 ; keyword general:gaps_out 0 ; keyword general:allow_tearing true ; keyword misc:vrr 2 ; keyword render:direct_scanout true"
                ;;
              off)
                pkill -CONT -x waybar 2>/dev/null || true
                systemctl --user start mako.service 2>/dev/null || true
                ;;
              *)
                echo "usage: hypr-gaming-mode on|off" >&2
                exit 2
                ;;
            esac
          '';
        })

        (pkgs.writeShellApplication {
          name = "game-scope";
          runtimeInputs = with pkgs; [gamemode gamescope];
          text = ''
            set -euo pipefail

            if [ "$#" -eq 0 ]; then
              cat >&2 <<'USAGE'
            usage: game-scope <command> [args...]

            Steam launch option:
              game-scope %command%

            Optional environment variables:
              GAMESCOPE_OUTPUT_WIDTH=1366
              GAMESCOPE_OUTPUT_HEIGHT=768
              GAMESCOPE_GAME_WIDTH=1024
              GAMESCOPE_GAME_HEIGHT=576
              GAMESCOPE_SCALER=fsr
              GAMESCOPE_REFRESH=60
            USAGE
              exit 64
            fi

            exec gamemoderun gamescope \
              --backend "''${GAMESCOPE_BACKEND:-sdl}" \
              -f \
              -W "''${GAMESCOPE_OUTPUT_WIDTH:-1366}" \
              -H "''${GAMESCOPE_OUTPUT_HEIGHT:-768}" \
              -w "''${GAMESCOPE_GAME_WIDTH:-1024}" \
              -h "''${GAMESCOPE_GAME_HEIGHT:-576}" \
              -F "''${GAMESCOPE_SCALER:-fsr}" \
              -r "''${GAMESCOPE_REFRESH:-60}" \
              -- "$@"
          '';
        })
      ];
    };
  };
}
