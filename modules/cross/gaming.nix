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
          "--mangoapp"
        ];
      };

      programs.steam = {
        gamescopeSession = {
          enable = true;
          args = [
            "--rt"
            "--mangoapp"
            "-W"
            "1366"
            "-H"
            "768"
            "-r"
            "60"
          ];
        };
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
        protontricks.enable = true;
      };

      users.users.${username}.extraGroups = lib.mkAfter [
        "gamemode"
        "video"
        "input"
      ];

      environment.systemPackages = with pkgs; [
        gamemode
        gamescope
        goverlay
        intel-gpu-tools
        libva-utils
        mangohud
        powertop
        vulkan-tools
      ];
    };

    home.module = {pkgs, ...}: {
      home.packages = [
        (pkgs.writeShellApplication {
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
      ];

      programs.mangohud = {
        enable = true;
        settings = {
          fps = true;
          frame_timing = true;
          frametime = true;
          gpu_stats = true;
          cpu_stats = true;
          cpu_temp = true;
          gpu_temp = true;
          throttling_status = true;
          fps_limit_method = "late";
          histogram = true;
          output_folder = "~/Documents/mangohud";
          log_duration = 60;
          autostart_log = false;
        };
      };
    };
  };
}
