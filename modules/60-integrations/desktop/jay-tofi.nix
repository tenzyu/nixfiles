{
  flake.modules.homeManager.jay = {config, lib, pkgs, ...}: let
    hasTerminal = config.local.features.alacritty.enable;
    tofiActions = pkgs.writeShellApplication {
      name = "jay-tofi-actions";
      runtimeInputs = [pkgs.tofi pkgs.unstable.jay] ++ lib.optional hasTerminal config.programs.alacritty.package;
      text = lib.replaceStrings ["@SHELL@"] [pkgs.runtimeShell] (builtins.readFile ../../../scripts/desktop/tofi-actions.sh);
    };
  in {
    config = lib.mkIf (config.local.features.jay.enable && config.local.features.tofi.enable) {
      home.packages = [tofiActions];
      local.jay.shortcuts = {
        logo-space = ''{ type = "exec", exec = ${builtins.toJSON (["${pkgs.tofi}/bin/tofi-drun" "--drun-launch=true"] ++ lib.optional hasTerminal "--terminal=alacritty")} }'';
        logo-r = ''{ type = "exec", exec = ["${lib.getExe tofiActions}", "run"] }'';
        logo-shift-space = ''{ type = "exec", exec = ["${lib.getExe tofiActions}", "desktop"] }'';
      } // lib.optionalAttrs hasTerminal {
        logo-shift-r = ''{ type = "exec", exec = ["${lib.getExe tofiActions}", "custom"] }'';
      };
    };
  };
}
