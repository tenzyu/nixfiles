{
  flake.features.starship.projections.homeManager.payload = {...}: {
    programs.starship = {
      enable = true;
    };
  };
}
