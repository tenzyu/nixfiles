{
  flake.features.zoxide.projections.homeManager.payload = {...}: {
    programs.zoxide = {
      enable = true;
    };
  };
}
