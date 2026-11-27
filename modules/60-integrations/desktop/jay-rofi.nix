{
  flake.modules.homeManager.jay = {config, lib, pkgs, ...}: let
    hasTerminal = config.local.features.alacritty.enable;
    rofi = config.programs.rofi.package;
    rofiActions = pkgs.writeShellApplication {
      name = "jay-rofi-actions";
      runtimeInputs = [rofi pkgs.unstable.jay] ++ lib.optional hasTerminal config.programs.alacritty.package;
      text = builtins.readFile ../../../scripts/desktop/interaction/rofi-actions.sh;
    };
    # Stock native Rofi modes; no shell wrapper for application or PATH launches.
    launch = mode: builtins.toJSON ([ (lib.getExe rofi) "-show" mode "-replace" ] ++ lib.optionals hasTerminal ["-terminal" "alacritty"]);
  in {
    config = lib.mkIf (config.local.features.jay.enable && config.local.features.rofi.enable) {
      home.packages = [rofiActions];
      local.jay.shortcuts = {
        logo-space = ''{ type = "exec", exec = ${launch "drun"} }'';
        logo-r = ''{ type = "exec", exec = ${launch "run"} }'';
        logo-shift-space = ''{ type = "exec", exec = ["${lib.getExe rofiActions}", "desktop"] }'';
      } // lib.optionalAttrs hasTerminal {
        logo-shift-r = ''{ type = "exec", exec = ["${lib.getExe rofiActions}", "custom"] }'';
      };
    };
  };
}
