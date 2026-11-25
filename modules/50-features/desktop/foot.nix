{
  flake.modules.homeManager.foot = {config, lib, pkgs, ...}: {
    config = lib.mkIf config.local.features.foot.enable {
      programs.foot = {
        enable = true;
        # Stock binary; no resident server when the last terminal closes.
        server.enable = false;
        settings = {
          main = {
            font = "FiraCode Nerd Font:size=11";
            pad = "10x10";
            # Preserve remote Herdr/SSH terminfo compatibility.
            term = "xterm-256color";
          };
          scrollback.lines = 10000;
          cursor.blink = "no";
          bell.system = "no";
          # Preserve the Alacritty security boundary, not foot's permissive default.
          security.osc52 = "copy-enabled";
        };
      };
    };
  };
}
