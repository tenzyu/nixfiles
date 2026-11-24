{
  flake.modules.homeManager.alacritty = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.alacritty.enable {
      programs.alacritty = {
        enable = true;
        package = pkgs.unstable.alacritty;
        settings = {
          font = {
            normal.family = "FiraCode Nerd Font";
            size = 11;
          };
          window = {
            padding = {
              x = 10;
              y = 10;
            };
            opacity = 1.0;
          };
          scrolling.history = 10000;
          cursor.style.blinking = "Never";
          bell.duration = 0;
        } // lib.optionalAttrs config.local.features.jay.enable {
          # Allow OSC 52 writes, never terminal-initiated clipboard reads.
          terminal.osc52 = "OnlyCopy";
        };
      };
    };
  };
}
