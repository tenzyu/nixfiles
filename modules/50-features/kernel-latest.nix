{...}: {
  flake.modules.nixos.kernel-latest = {pkgs, ...}: {
    boot.kernelPackages = pkgs.linuxPackages_latest;
  };
}
