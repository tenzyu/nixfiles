{
  flake.modules.homeManager.jay = {config, lib, osConfig ? null, ...}: let
    hasIme = osConfig != null && osConfig.i18n.inputMethod.enable && osConfig.i18n.inputMethod.type == "fcitx5";
    ime = if hasIme then osConfig.i18n.inputMethod.package else null;
    restart = ''{ prog = "${ime}/bin/fcitx5", args = ["-r"], privileged = true }'';
  in {
    config = lib.mkIf (config.local.features.jay.enable && hasIme) {
      # Start after the clipboard capture hook, as in the accepted baseline.
      local.jay.startupActions = lib.mkAfter [
        ''{ type = "exec", exec = ${restart} }''
      ];
      local.jay.shortcuts = {
        logo-ctrl-i = ''{ type = "exec", exec = ${restart} }'';
        logo-i = ''{ type = "exec", exec = ["${ime}/bin/fcitx5-remote", "-t"] }'';
      };
    };
  };
}
