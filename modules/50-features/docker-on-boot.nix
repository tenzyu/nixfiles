{
  flake.modules.nixos.docker-on-boot = {
    virtualisation.docker.enableOnBoot = true;
  };
}
