{...}: {
  flake.modules.homeManager.packagesDesktop = {pkgs, ...}: {
    local.pkgs.useUnstable = true;

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
