{
  flake.features.rofi.projections.homeManager.payload = {...}: {
    programs.rofi = {
      enable = true;
    };
  };
}
