{...}: {
  flake.modules.homeManager.packagesDesktop = {pkgs, ...}: {
    home.packages = with pkgs; [
      brightnessctl
      cliphist
      dunst
      obs-studio
      pavucontrol
      playerctl
      wl-clipboard
      unstable.grimblast
    ];
  };
}
