{
  flake.features.tenzyu-cli.projections.homeManager.payload = {...}: {
    local.features = {
      common.enable = true;
      packages-common.enable = true;
      zsh.enable = true;
      btop.enable = true;
      fastfetch.enable = true;
      fzf.enable = true;
      git.enable = true;
      neovim.enable = true;
      starship.enable = true;
      tmux.enable = true;
      yazi.enable = true;
      zoxide.enable = true;
    };
  };
}
