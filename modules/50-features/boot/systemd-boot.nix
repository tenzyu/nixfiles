{lib, ...}: {
  flake.modules.nixos.systemd-boot = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.systemd-boot.enable {
      boot.loader.grub.enable = lib.mkForce false;
      boot.loader.systemd-boot.enable = lib.mkDefault true;
      boot.loader.systemd-boot.configurationLimit = lib.mkDefault 5;
      boot.loader.efi.efiSysMountPoint = lib.mkDefault "/boot";
      boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;
    };
  };
}
