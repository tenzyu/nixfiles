{
  flake.modules.homeManager.jay = {config, lib, ...}: {
    config = lib.mkIf (config.local.features.jay.enable && config.local.features.alacritty.enable) {
      local.jay.shortcuts.logo-Return = ''{ type = "exec", exec = "${lib.getExe config.programs.alacritty.package}" }'';
      # Allow OSC 52 writes, never terminal-initiated clipboard reads.
      programs.alacritty.settings.terminal.osc52 = "OnlyCopy";
    };
  };
}
