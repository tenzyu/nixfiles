{
  flake.modules.nixos.bluetooth = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.bluetooth.enable {
      services.blueman.enable = lib.mkDefault true;
      hardware.bluetooth = {
        enable = lib.mkDefault true;
        powerOnBoot = lib.mkDefault true;
      };
    };
  };
}
