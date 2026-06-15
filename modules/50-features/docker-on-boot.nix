{
  config,
  ...
}: {
  flake.modules.nixos.docker-on-boot = {config, lib, ...}: {
    config = lib.mkIf config.local.features.docker-on-boot.enable {
      virtualisation.docker.enableOnBoot = true;
    };
  };
}
