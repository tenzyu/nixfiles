{lib, ...}: {
  flake.modules.nixos.qemu-guest-profile = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.qemu-guest-profile.enable {
      services.qemuGuest.enable = lib.mkDefault true;

      boot.initrd.availableKernelModules = lib.mkAfter [
        "virtio_pci"
        "virtio_scsi"
        "virtio_blk"
        "virtio_net"
      ];

      boot.initrd.kernelModules = lib.mkAfter [
        "virtio_balloon"
        "virtio_console"
      ];
    };
  };
}
