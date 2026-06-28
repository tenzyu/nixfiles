{config, ...}: {
  flake.features.qemu-guest-agent.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    services.qemuGuest.enable = true;
  };
}
