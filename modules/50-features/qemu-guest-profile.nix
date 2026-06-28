{...}: {
  flake.features.qemu-guest-profile.projections.nixos.payload = {
    lib,
    ...
  }: {
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
}
