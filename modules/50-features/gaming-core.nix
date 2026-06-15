{
  flake.effects.gaming-core = {
    user = {user, ...}: {
      config = {
        users.users.${user.name}.extraGroups = [
          "gamemode"
          "video"
          "input"
        ];
      };
    };
  };

  flake.modules.nixos.gaming-core = {pkgs, ...}: {
    programs.gamemode = {
      enable = true;
      enableRenice = true;
      settings = {
        general = {
          inhibit_screensaver = 0;
          renice = 10;
          softrealtime = "auto";
        };
      };
    };

    programs.gamescope = {
      enable = true;
      capSysNice = true;
      args = ["--rt"];
    };

    environment.systemPackages = with pkgs; [
      gamemode
      gamescope
      intel-gpu-tools
      libva-utils
      powertop
      vulkan-tools
    ];
  };

  flake.modules.homeManager.gaming-core = {pkgs, ...}: {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "game-scope";
        runtimeInputs = with pkgs; [
          gamemode
          gamescope
        ];
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
}
