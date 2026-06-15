{
  flake.modules.homeManager.yazi = {
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
