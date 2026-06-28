{lib, ...}: {
  flake.features.time.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    time.timeZone = lib.mkDefault "Asia/Tokyo";
  };
}
