{
  lib,
  config,
  ...
}: {
  flake.modules.nixos.kernel-latest = {
    config,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.kernel-latest.enable {
      boot.kernelPackages = pkgs.linuxPackages_latest;
    };
  };
}
