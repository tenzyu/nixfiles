{
  flake.modules.homeManager.desktop-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.desktop-tools.enable {
      home.packages = with pkgs; [
        brightnessctl
        libnotify
        pavucontrol
        playerctl
        wl-clipboard
      ];
    };
  };
}
