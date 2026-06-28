{...}: {
  flake.features.docker-rootful.projections.nixos.payload = {...}: {
    virtualisation.docker.enable = true;
  };
}
