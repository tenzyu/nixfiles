{
  flake.modules.nixos.NAME = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.NAME.enable {
        # services.blueman.enable = lib.mkDefault true;
        # hardware.bluetooth = {
        # enable = lib.mkDefault true;
        # jpowerOnBoot = lib.mkDefault true;
        # };
    };
  };
}
