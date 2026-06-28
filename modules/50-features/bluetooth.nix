{
  flake.features.bluetooth.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    services.blueman.enable = lib.mkDefault true;
    hardware.bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault true;
    };
  };
}
