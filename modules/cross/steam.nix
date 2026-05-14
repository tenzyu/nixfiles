{
  local.cross.definitions.steam = let
    steamPackage = pkgs:
      pkgs.unstable.steam.override {
        extraEnv = {
          SDL_VIDEO_DRIVER = "wayland,x11";
          SDL_VIDEODRIVER = "wayland,x11";
        };

        extraPreBwrapCmds = ''
          # Valve's startup script prints noisy find(1) errors when steam.pid
          # points at a recycled process whose /proc fd directory is private.
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
        policy.pkgs.allowUnfreeNames = ["steam" "steam-unwrapped"];
      }
    ];

    nixos.module = {pkgs, ...}: {
      programs.steam = {
        enable = true;
        package = steamPackage pkgs;
      };
    };
    home.packages = pkgs: [
      (steamPackage pkgs)
    ];
  };
}
