{
  flake.modules.homeManager.packages-desktop = {config, lib, pkgs, ...}: {
    config = lib.mkIf config.local.features.packages-desktop.enable {
      home.packages = with pkgs; [
        brightnessctl
        cliphist
        libnotify
        obs-studio
        pavucontrol
        playerctl
        wl-clipboard
        unstable.grimblast
      ];
    };
  };
}
