{...}: {
  flake.modules.homeManager.packagesDesktop = {pkgs, ...}: {
    local.pkgs.useUnstable = true;

    home.packages = with pkgs; [
      brightnessctl
      cliphist
      dunst
      kdePackages.dolphin
      kdePackages.ffmpegthumbs
      kdePackages.kdegraphics-thumbnailers
      kdePackages.kimageformats
      kdePackages.kio-extras
      libheif
      obs-studio
      pavucontrol
      playerctl
      qt6.qtimageformats
      wl-clipboard
      unstable.grimblast
    ];
  };
}
