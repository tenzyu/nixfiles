{...}: {
  flake.modules.homeManager.packagesDesktop = {pkgs, ...}: {
    local.pkgs.useUnstable = true;

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
