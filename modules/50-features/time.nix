{lib, ...}: {
  flake.modules.nixos.time = {config, lib, ...}: {
    config = lib.mkIf config.local.features.time.enable {
      time.timeZone = lib.mkDefault "Asia/Tokyo";
    };
  };
}
