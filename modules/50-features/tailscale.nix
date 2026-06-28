{config, ...}: {
  flake.features.tailscale.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    services.tailscale.enable = true;
  };
}
