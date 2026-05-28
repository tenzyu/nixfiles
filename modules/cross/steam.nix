{
  local.cross.definitions.steam = let
    steamPackage = pkgs:
      pkgs.unstable.steam.override {
        extraEnv = {
          SDL_VIDEO_DRIVER = "wayland,x11";
          SDL_VIDEODRIVER = "wayland,x11";
        };

        extraPreBwrapCmds = ''
          # Valve's startup script can choke on a stale steam.pid that points at
          # a recycled process with private /proc/fd permissions.
          steam_pid_file="$HOME/.steam/steam.pid"
          if [ -r "$steam_pid_file" ]; then
            steam_pid="$(cat "$steam_pid_file" 2>/dev/null || true)"
            if [[ "$steam_pid" =~ ^[0-9]+$ ]]; then
              steam_proc="/proc/$steam_pid"
              if [ -e "$steam_proc" ] && [ ! -r "$steam_proc/fd" ]; then
                rm -f "$steam_pid_file"
              fi
            fi
          fi
        '';
      };
  in {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
      {
        policy.pkgs.allowUnfreeNames = ["steam" "steam-original" "steam-unwrapped" "steam-run"];
      }
    ];

    nixos.module = {pkgs, ...}: {
      programs.steam = {
        enable = true;
        package = steamPackage pkgs;
        protontricks.enable = true;

        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];

        # Dedicated display-manager session: Steam inside gamescope.
        # For per-game usage from the normal Hyprland session, use:
        #   game-scope %command%
        gamescopeSession = {
          enable = true;
          args = [
            "--rt"
            "-W"
            "1366"
            "-H"
            "768"
            "-r"
            "60"
          ];
          steamArgs = [
            "-gamepadui"
          ];
        };
      };
    };

    home.module = {
      cross,
      pkgs,
      ...
    }: {
      home.packages =
        [
          (pkgs.writeShellApplication {
            name = "steam-gaming";
            runtimeInputs = with pkgs; [gamemode gamescope];
            text = ''
              set -euo pipefail

              if command -v hypr-gaming-mode >/dev/null 2>&1; then
                hypr-gaming-mode on || true
                trap 'hypr-gaming-mode off || true' EXIT INT TERM
              fi

              exec gamemoderun gamescope \
                --backend "''${GAMESCOPE_BACKEND:-sdl}" \
                --steam \
                --rt \
                -f \
                -W "''${GAMESCOPE_WIDTH:-1366}" \
                -H "''${GAMESCOPE_HEIGHT:-768}" \
                -r "''${GAMESCOPE_REFRESH:-60}" \
                -- steam "$@"
            '';
          })
        ]
        ++ (cross.select {
          nixos = [];
          standalone = [
            (steamPackage pkgs)
          ];
        });

      xdg.desktopEntries.steam-gaming = {
        name = "Steam Gaming";
        genericName = "Steam in GameMode + Gamescope";
        exec = "steam-gaming";
        terminal = false;
        categories = ["Game"];
      };
    };
  };
}
