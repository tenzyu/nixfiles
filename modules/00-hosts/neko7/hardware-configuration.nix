{
  flake.modules.nixos.neko7-hardware = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.neko7-hardware.enable {
      boot.initrd.availableKernelModules = ["nvme" "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod"];
      boot.initrd.kernelModules = [];
      boot.kernelModules = ["kvm-amd"];
      boot.extraModulePackages = [];

      fileSystems."/" = {
        device = "/dev/disk/by-label/NEKO7_ROOT";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-label/NEKO7_ESP";
        fsType = "vfat";
      };

      swapDevices = [];

      networking.useDHCP = lib.mkDefault true;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    };
  };
}
