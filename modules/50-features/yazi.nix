{
  flake.features.yazi.projections.homeManager.payload = {...}: {
    programs.yazi = {
      enable = true;
      enableZshIntegration = true;

      settings = {
        mgr = {
          show_hidden = true;
        };
      };
    };
  };
}
