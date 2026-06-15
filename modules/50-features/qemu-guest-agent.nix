{
  config,
  ...
}: {
  flake.modules.nixos.qemu-guest-agent = {config, lib, ...}: {
    config = lib.mkIf config.local.features.qemu-guest-agent.enable {
      services.qemuGuest.enable = true;
    };
  };
}
