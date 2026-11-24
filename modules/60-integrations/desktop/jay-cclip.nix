{
  flake.modules.homeManager.jay = {config, lib, pkgs, ...}: let
    jay = pkgs.unstable.jay;
    hasCclip = config.local.features.cclip.enable;
    cclip = pkgs.unstable.callPackage ../../../assets/packages/cclip.nix {};
    picker = pkgs.writeShellApplication {
      name = "cclip-picker";
      runtimeInputs = [cclip pkgs.unstable.jay pkgs.tofi pkgs.coreutils pkgs.util-linux pkgs.libnotify];
      text = builtins.readFile ../../../scripts/desktop/cclip-picker.sh;
    };
    clipboardHistory = ''
      selection="$(${lib.getExe pkgs.cliphist} list | rofi -dmenu -replace -i)" || exit 0
      [ -n "$selection" ] || exit 0
      printf '%s\n' "$selection" | ${lib.getExe pkgs.cliphist} decode | ${lib.getExe jay} run-privileged ${lib.getExe' pkgs.wl-clipboard "wl-copy"}
    '';
  in {
    config = lib.mkIf config.local.features.jay.enable {
      home.packages = if hasCclip then [picker] else [pkgs.cliphist];
      local.jay.startupActions = if hasCclip then [
        ''{ type = "exec", exec = { prog = "cclip-start", args = [], privileged = true } }''
      ] else [
        ''{ type = "exec", exec = { prog = "${lib.getExe' pkgs.wl-clipboard "wl-paste"}", args = ["--type", "text", "--watch", "${lib.getExe pkgs.cliphist}", "store"], privileged = true } }''
        ''{ type = "exec", exec = { prog = "${lib.getExe' pkgs.wl-clipboard "wl-paste"}", args = ["--type", "image", "--watch", "${lib.getExe pkgs.cliphist}", "store"], privileged = true } }''
      ];
      local.jay.shortcuts.logo-v = if hasCclip
        then ''{ type = "exec", exec = ["cclip-picker"] }''
        else ''{ type = "exec", exec = { shell = ${builtins.toJSON clipboardHistory} } }'';
    };
  };
}
