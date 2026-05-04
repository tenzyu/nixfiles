{
  flake.modules.nixos.dockerRootless = {
    virtualisation.docker.rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
