{
  flake.modules.nixos.dockerAutoPrune = {
    virtualisation.docker.autoPrune.enable = true;
  };
}
