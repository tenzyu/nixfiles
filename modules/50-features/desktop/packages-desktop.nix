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
        # NOTE: CEF 減らしたかったけどビルド必要だったから諦めるわ.
        # package = pkgs.obs-studio.override {
        #   browserSupport = false;
        # };
      };

      home.packages =
        (with pkgs; [
          brightnessctl
          cliphist
          libnotify
          pavucontrol
          playerctl
          wl-clipboard
          unstable.grimblast
          # vrcx
        ])
        ++ lib.optional (!config.local.features.splitcast-capture.enable) pkgs.easyeffects;
    };
  };
}
