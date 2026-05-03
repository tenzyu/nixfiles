{...}: {
  flake.modules.homeManager.packagesDesktop = {pkgs, ...}: {
    home.packages = with pkgs; [
      brightnessctl
      cliphist
      dunst
      firefox
      obs-studio
      pavucontrol
      playerctl
      wl-clipboard
      unstable.grimblast
    ];
  };
}
