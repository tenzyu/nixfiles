{
  flake.features.packages-desktop.projections.homeManager.payload = {pkgs, ...}: {
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
}
