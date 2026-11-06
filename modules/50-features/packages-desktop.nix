{
  flake.modules.homeManager.packages-desktop = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.packages-desktop.enable {
      programs.obs-studio = {
        enable = true;
        plugins = [pkgs.obs-studio-plugins.obs-vkcapture];
      };

      home.packages =
        (with pkgs; [
          brightnessctl
          cliphist
          libnotify
          obs-studio-plugins.obs-vkcapture
          pavucontrol
          playerctl
          wl-clipboard
          unstable.grimblast
          vrcx
        ])
        ++ lib.optional (!config.local.features.splitcast-capture.enable) pkgs.easyeffects;
    };
  };
}
