{
  flake.modules.homeManager.git = {
    programs.git = {
      enable = true;
      settings = {
        alias = {
          st = "status --short --branch";
          lg = "log --oneline --graph --decorate --all";
          last = "log -1 --stat";
        };
        color.ui = true;
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
      };
    };

    programs.delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
      };
    };
  };
}
