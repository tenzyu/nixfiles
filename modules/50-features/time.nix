{lib, ...}: {
  flake.modules.nixos.time = {
    time.timeZone = lib.mkDefault "Asia/Tokyo";
  };
}
