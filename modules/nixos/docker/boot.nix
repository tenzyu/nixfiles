{
  flake.modules.nixos.dockerOnBoot = {
    virtualisation.docker.enableOnBoot = true;
  };
}
