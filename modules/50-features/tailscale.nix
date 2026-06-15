{config, ...}: {
  flake.modules.nixos.tailscale = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.tailscale.enable {
      services.tailscale.enable = true;
    };
  };
}
