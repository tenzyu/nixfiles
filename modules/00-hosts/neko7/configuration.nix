{...}: {
  configurations.nixos.neko7.module = {
    # First admission keeps the paths already used by the shell and user services.
    home-manager.users.tenzyu.local.homeMigration.adoptedRoutes = {
      node-history = "intended";
      npm = "intended";
      rust = "intended";
      zsh = "intended";
    };

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
        # Physical machine, boot, kernel, storage
        neko7-hardware.enable = true;
        systemd-boot.enable = true;
        qemu-guest-profile.enable = true;
        kernel-latest.enable = false;
        nvidia-graphics.enable = true;

        # Network and ingress boundary
        networkmanager.enable = true;
        disable-ipv6.enable = true;
        resolvconf-blacklist-gateway.enable = true;
        tailscale.enable = true;
        ssh.enable = true;
        tailnet-ingress.enable = true;
        preview-gateway.enable = true;

        # Nix and execution substrate
        nix.enable = true;
        nix-remote-builder.enable = true;
        incus.enable = true;
        docker-rootless.enable = true;
        codex-sandbox.enable = true;
        t3code-browser.enable = true;
        stub-ld.enable = true;
        nix-ld.enable = true;
        llama-cpp-cuda.enable = true;

        # Operator telemetry, credentials and control plane
        sops-nix.enable = true;
        platform-observability.enable = true;
        execution-discovery.enable = true;
        t3code-tailnet.enable = true;

        # Persistent workload placement
        splitcast-production.enable = true;
        game-ark.enable = false;
        game-rust.enable = false;
        game-minecraft.enable = true;
        game-srv.enable = true;
        game-server-tools.enable = true;
        neko7-workload-profiles.enable = true;

        # Common host environment
        time.enable = true;
        locale.enable = true;
        ja-extra-locales.enable = true;
        us-xserver-keyboard.enable = true;
        fonts.enable = true;
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
        # The production role is deployed independently of the host generation.
        splitcast-production.enable = false;
        splitcast-production-profile.enable = true;
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
