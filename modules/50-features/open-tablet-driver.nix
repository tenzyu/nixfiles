{
  config,
  ...
}: {
  flake.modules.nixos.open-tablet-driver = {config, lib, ...}: {
    config = lib.mkIf config.local.features.open-tablet-driver.enable {
      hardware.opentabletdriver.enable = true;
    };
  };
}
