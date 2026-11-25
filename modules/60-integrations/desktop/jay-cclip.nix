{
  flake.modules.homeManager.jay = {config, lib, pkgs, ...}: let
    cclip = pkgs.unstable.callPackage ../../../assets/packages/cclip.nix {};
    picker = pkgs.writeShellApplication {
      name = "cclip-picker";
      runtimeInputs = [cclip pkgs.unstable.jay config.programs.rofi.package pkgs.coreutils pkgs.util-linux pkgs.libnotify];
      text = builtins.readFile ../../../scripts/desktop/cclip-picker.sh;
    };
  in {
    config = lib.mkIf (config.local.features.jay.enable && config.local.features.cclip.enable) {
      local.jay.startupActions = [
        ''{ type = "exec", exec = { prog = "cclip-start", args = [], privileged = true } }''
      ];
      home.packages = lib.optional config.local.features.rofi.enable picker;
      local.jay.shortcuts.logo-v = lib.mkIf config.local.features.rofi.enable
        ''{ type = "exec", exec = ["cclip-picker"] }'';
    };
  };
}
