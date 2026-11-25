{
  flake.modules.homeManager.jay = {config, lib, ...}: {
    config = lib.mkIf (config.local.features.jay.enable && config.local.features.foot.enable) {
      assertions = [{
        assertion = !config.local.features.alacritty.enable;
        message = "Select exactly one Jay terminal binding (foot or Alacritty).";
      }];
      local.jay.shortcuts.logo-Return = ''{ type = "exec", exec = "${lib.getExe config.programs.foot.package}" }'';
    };
  };
}
