{
  config,
  ...
}: {
  flake.modules.nixos.grub-sda = {config, lib, ...}: {
    config = lib.mkIf config.local.features.grub-sda.enable {
      boot.loader.grub.enable = true;
      boot.loader.grub.device = "/dev/sda";
      boot.loader.grub.useOSProber = true;
    };
  };
}
