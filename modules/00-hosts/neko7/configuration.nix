{...}: {
  configurations.nixos.neko7.module = {
    # Keep the T3 user service running after logout and across reboots.
    users.users.tenzyu.linger = true;
    # Host-specific uplink belongs to the host, not to a game bundle.
    networking.nat = {
      enable = true;
      externalInterface = "ens18";
    };
    # Android (nekosm1) access to neko7; preserve existing authorized keys.
    users.users.tenzyu.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICFSHWkNf1cLdqztiXeoYTmN5eetgZLKaupqH3hk9uBL neko7 key"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDY3E3vfeka0KAjF247PPJ0xwQSaChBDAjlT//oPUENp nekosm1-termux-neko7"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEA48dVV7Lh9zkdbfeZ3tmvaG0IdKX4nspUNqedg0pTj herdr"
    ];

    local = {
      context = {
        flakePath = "/home/tenzyu/.nixfiles";
        systemStateVersion = "26.05";
      };
      features = {
        neko7-hardware.enable = true;
        nix.enable = true;
        time.enable = true;
        locale.enable = true;
        ssh.enable = true;
        tailscale.enable = true;
        t3code-tailnet.enable = true;
        splitcast-production.enable = true;
        # Keep ARK and Rust definitions available without deploying them.
        # Minecraft is the only selected game container on neko7.
        game-ark.enable = false;
        game-rust.enable = false;
        game-minecraft.enable = true;
        # TODO(srv-cutover): change to true only after the stopped-container
        # copy, checksum verification and rollback preparation in
        # docs/game-server-srv-migration.md.
        game-srv.enable = false;
        # TODO(sops-bootstrap): enable only after adding the encrypted
        # secrets/neko7.yaml and .sops.yaml recipient policy in a commit,
        # verifying the decryption key on neko7, and approving activation.
        game-secrets-sops.enable = false;
        game-server-tools.enable = true;
        resolvconf-blacklist-gateway.enable = true;
        disable-ipv6.enable = true;
        systemd-boot.enable = true;
        # Proxmox is a deployment context; the actual NixOS capability is QEMU guest support.
        qemu-guest-profile.enable = true;
        nvidia-graphics.enable = true;
        kernel-latest.enable = false;
        networkmanager.enable = true;
        ja-extra-locales.enable = true;
        us-xserver-keyboard.enable = true;
        fonts.enable = true;
        stub-ld.enable = true;
        nix-ld.enable = true;
        docker-rootless.enable = true;
        llama-cpp-cuda.enable = true;
        nix-remote-builder.enable = true;
      };
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
        splitcast-production.enable = true;
        zsh.enable = true;
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

        catppuccin.enable = true;
        nix-access.enable = true;
        nh.enable = true;
        nix-tools.enable = true;
        git-tools.enable = true;
        herdr.enable = true;
        rtk.enable = true;
        opencode-direnv.enable = true;
        codex.enable = true;
        t3code-neko7.enable = true;
      };
    };
  };
}
