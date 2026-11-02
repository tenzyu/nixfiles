{role}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.features."splitcast-${role}";
in {
  imports = lib.optional (role == "production") ./headless-display.nix;

  config = lib.mkIf cfg.enable {
    programs.gpu-screen-recorder.enable = lib.mkIf (role == "capture") (lib.mkDefault true);
    security.rtkit.enable = lib.mkDefault true;
    services.pipewire = {
      enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
      alsa.enable = lib.mkDefault true;
      wireplumber.enable = lib.mkDefault true;
    };
    hardware.graphics.enable = lib.mkDefault true;
    environment.systemPackages = [pkgs.v4l-utils];
  };
}
