{
  flake.modules.nixos.docker-auto-prune = {
    virtualisation.docker.autoPrune.enable = true;
  };
}
