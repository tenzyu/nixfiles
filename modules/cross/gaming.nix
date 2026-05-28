{config, ...}: let
  inherit (config.me) username;
in {
  local.cross.definitions.gaming = {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
      {
        policy.pkgs.allowUnfreeNames = ["steam" "steam-unwrapped"];
      }
    ];

    nixos.module = {
      lib,
      pkgs,
      ...
    }: {
      programs.gamemode = {
        enable = true;
        settings = {
          general = {
            inhibit_screensaver = 0;
            renice = 10;
          };
          custom = {
            start = "${pkgs.writeShellScript "gamemode-start" ''
              systemctl --user stop hyprpaper.service 2>/dev/null || true
              pkill -STOP -x waybar 2>/dev/null || true
              pkill -STOP -x dunst 2>/dev/null || true
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
            ''}";
            end = "${pkgs.writeShellScript "gamemode-end" ''
              pkill -CONT -x waybar 2>/dev/null || true
              pkill -CONT -x dunst 2>/dev/null || true
              systemctl --user start hyprpaper.service 2>/dev/null || true
            ''}";
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
      };

      users.users.${username}.extraGroups = lib.mkAfter [
        "wheel"
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
        protontricks
        vulkan-tools
      ];
    };

    home.module = {
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
