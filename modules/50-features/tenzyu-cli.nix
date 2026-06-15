{
  flake.modules.homeManager.tenzyu-cli = {config, lib, ...}: {
    config = lib.mkIf config.local.features.tenzyu-cli.enable {
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
  };
}
