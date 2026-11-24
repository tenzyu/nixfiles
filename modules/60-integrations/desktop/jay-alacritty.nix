{
  flake.modules.homeManager.jay = {config, lib, pkgs, ...}: let
    terminal = if config.programs.alacritty.enable then config.programs.alacritty.package else pkgs.unstable.alacritty;
  in {
    config = lib.mkIf config.local.features.jay.enable {
      home.packages = lib.optional (!config.programs.alacritty.enable) terminal;
      local.jay.shortcuts.logo-Return = ''{ type = "exec", exec = "${lib.getExe terminal}" }'';
      # Allow OSC 52 writes, never terminal-initiated clipboard reads.
      programs.alacritty.settings.terminal.osc52 = lib.mkIf config.local.features.alacritty.enable "OnlyCopy";
    };
  };
}
