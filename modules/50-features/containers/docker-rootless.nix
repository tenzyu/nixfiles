{
  flake.modules.nixos.docker-rootless = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.docker-rootless.enable {
      virtualisation.docker.rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  };
}
