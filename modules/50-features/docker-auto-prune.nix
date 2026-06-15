{
  config,
  lib,
  ...
}: {
  flake.modules.nixos.docker-auto-prune = {config, lib, ...}: {
    config = lib.mkIf config.local.features.docker-auto-prune.enable {
      virtualisation.docker.autoPrune.enable = true;
    };
  };
}
