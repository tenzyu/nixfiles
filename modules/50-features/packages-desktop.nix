{...}: {
  flake.modules.homeManager.packages-desktop = {pkgs, ...}: {
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
