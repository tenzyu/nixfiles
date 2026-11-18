{...}: {
  configurations.nixos.neko6.module = {
    local.features = {
      wsl-integration.enable = true;
      nix.enable = true;
      time.enable = true;
      locale.enable = true;
      passwordless-sudo.enable = true;
      ssh.enable = true;
      ssh-debug.enable = true;
      empty-nix-access-tokens.enable = true;
      nix-ld.enable = true;
      docker-rootful.enable = true;
      docker-on-boot.enable = true;
      docker-auto-prune.enable = true;
    };

    local.users.tenzyu = {
      enable = true;
      context = {
        isAdmin = true;
        homeStateVersion = "26.05";
        email = "tenzyu.on@gmail.com";
        homeDirectory = "/home/tenzyu";
      };

      features = {
        common.enable = true;
        packages-common.enable = true;
        btop.enable = true;
        fastfetch.enable = true;
        fzf.enable = true;
        git.enable = true;
        neovim.enable = true;
        starship.enable = true;
        tmux.enable = false;
        yazi.enable = true;
        zoxide.enable = true;

        wsl-default-user.enable = true;
        docker-user-access.enable = true;
        ozone-wayland.enable = true;
      };
    };
  };
}
