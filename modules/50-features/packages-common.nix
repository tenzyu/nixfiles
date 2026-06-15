{
  flake.modules.homeManager.packages-common = {config, lib, pkgs, ...}: {
    config = lib.mkIf config.local.features.packages-common.enable {
      home.packages = with pkgs; [
        bat
        bitwarden-cli
        dust
        eza
        fd
        glow
        pay-respects
        ripgrep
        tealdeer
        xclip
        xdg-ninja
      ];
    };
  };
}
