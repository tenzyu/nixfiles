{...}: {
  configurations.nixos.neko7.module = {
    local.features = {
      neko7-hardware.enable = true;
      nix.enable = true;
      zsh.enable = true;
      time.enable = true;
      locale.enable = true;
      ssh.enable = true;
      tailscale.enable = true;
      resolvconf-blacklist-gateway.enable = true;
      disable-ipv6.enable = true;
      systemd-boot.enable = true;
      proxmox-guest.enable = true;
      nvidia-graphics.enable = true;
      kernel-latest.enable = true;
      networkmanager.enable = true;
      ja-extra-locales.enable = true;
      us-xserver-keyboard.enable = true;
      fonts.enable = true;
      stub-ld.enable = true;
      nix-ld.enable = true;
      docker-rootless.enable = true;
      llama-cpp-cuda.enable = true;
    };

    local.users.tenzyu = {
      enable = true;
      isAdmin = true;
      homeStateVersion = "26.05";
      email = "tenzyu.on@gmail.com";
      homeDirectory = "/home/tenzyu";

      features = {
        tenzyu-cli.enable = true;
        catppuccin.enable = true;
        nix-access.enable = true;
        nix-tools.enable = true;
        git-tools.enable = true;
      };
    };
  };
}
