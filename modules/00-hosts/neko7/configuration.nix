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
      # Final shape:
      #   neko7       = admin node
      #   neko7-ark   = ARK player node
      #   neko7-rust  = Rust player node
      game-server-containers.enable = true;
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
        herdr.enable = true;
      };
    };

    local.containers.neko7-rust = {
      backend = "nixos-container";
      autoStart = false;
      privateNetwork = true;
      enableTun = true;
      hostAddress = "10.77.20.1";
      localAddress = "10.77.20.2";

      nat = {
        enable = true;
        externalInterface = "ens18";
      };

      bindMounts = {
        "/home/game-rust" = {
          hostPath = "/home/game-rust";
          isReadOnly = false;
        };

        "/var/lib/tailscale" = {
          hostPath = "/home/game-rust/.state/tailscale";
          isReadOnly = false;
        };
      };

      features = {
        tailscale-node = {
          enable = true;
          hostname = "neko7-rust";
          authKeyFile = "/home/game-rust/secrets/tailscale-authkey";
          udpPorts = [
            28015
            28017
          ];
          tcpPorts = [
            28016
            28082
          ];
        };

        rust-dedicated = {
          enable = true;
          user = "game-rust";
          uid = 27008;
          gid = 27008;
          home = "/home/game-rust";
          installDir = "/home/game-rust/rust/server";
          backupDir = "/home/game-rust/rust/backups";
          envFile = "/home/game-rust/secrets/rust.env";
        };

        game-rcon-node.enable = true;
      };
    };
  };
}
