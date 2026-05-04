{...}: {
  flake.modules.nixos.kernelLatest = {pkgs, ...}: {
    boot.kernelPackages = pkgs.linuxPackages_latest;
  };
}
