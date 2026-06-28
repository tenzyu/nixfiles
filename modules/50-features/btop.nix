{
  flake.features.btop.projections.homeManager.payload = {...}: {
    programs.btop = {
      enable = true;
      settings = {
        vim_keys = true;
        proc_sorting = "memory";
      };
    };
  };
}
