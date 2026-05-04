{lib, ...}: {
  flake.modules.nixos.bluetooth = {
    services.blueman.enable = lib.mkDefault true;
    hardware.bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault true;
    };
  };
}
