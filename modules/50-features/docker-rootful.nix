{
  config,
  ...
}: {
  flake.modules.nixos.docker-rootful = {config, lib, ...}: {
    config = lib.mkIf config.local.features.docker-rootful.enable {
      virtualisation.docker.enable = true;
    };
  };
}
