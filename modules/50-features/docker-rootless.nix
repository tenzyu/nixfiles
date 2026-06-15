{
  flake.modules.nixos.docker-rootless = {
    virtualisation.docker.rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
