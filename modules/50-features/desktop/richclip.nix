{
  flake.modules.homeManager.richclip = {
    config,
    lib,
    pkgs,
    ...
  }: let
    richclip = pkgs.unstable.callPackage ../../../assets/packages/richclip.nix {};
    # Only richclipd needs the privileged Wayland socket. Keep the picker
    # bounded, independent of tofi-drun's lock, and entirely on demand.
    picker = pkgs.writeShellApplication {
      name = "richclip-picker";
      runtimeInputs = [richclip pkgs.jq pkgs.tofi pkgs.coreutils pkgs.util-linux pkgs.libnotify];
      text = builtins.readFile ../../../scripts/desktop/richclip-picker.sh;
    };
  in {
    config = lib.mkIf config.local.features.richclip.enable {
      home.packages = [richclip picker];
    };
  };
}
