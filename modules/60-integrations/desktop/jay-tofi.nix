{
  flake.modules.homeManager.jay = {config, lib, pkgs, ...}: let
    jay = pkgs.unstable.jay;
    terminal = if config.programs.alacritty.enable then config.programs.alacritty.package else pkgs.unstable.alacritty;
    hasTofi = config.local.features.tofi.enable;
    tofiActions = pkgs.writeShellApplication {
      name = "jay-tofi-actions";
      runtimeInputs = [pkgs.tofi jay terminal];
      text = lib.replaceStrings ["@SHELL@"] [pkgs.runtimeShell] (builtins.readFile ../../../scripts/desktop/tofi-actions.sh);
    };
  in {
    config = lib.mkIf config.local.features.jay.enable {
      home.packages = lib.optional hasTofi tofiActions;
      local.jay.shortcuts = {
        logo-space = ''{ type = "exec", exec = ${builtins.toJSON (if hasTofi then ["${pkgs.tofi}/bin/tofi-drun" "--drun-launch=true" "--terminal=alacritty"] else ["rofi" "-show" "drun"])} }'';
      } // (if hasTofi then {
        logo-r = ''{ type = "exec", exec = ["${lib.getExe tofiActions}", "run"] }'';
        logo-shift-r = ''{ type = "exec", exec = ["${lib.getExe tofiActions}", "custom"] }'';
        logo-shift-space = ''{ type = "exec", exec = ["${lib.getExe tofiActions}", "desktop"] }'';
        logo-ctrl-shift-r = ''"reload-config-toml"'';
      } else {
        logo-shift-r = ''"reload-config-toml"'';
      });
    };
  };
}
