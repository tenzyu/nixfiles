{
  configurations.nixos.neko5.module = {
    home-manager.users.tenzyu.imports = [({lib, ...}: {
      # Install the config files normally. Apply reloads at the next app launch,
      # outside Home Manager activation and its protected HOME write checks.
      xdg.configFile = lib.genAttrs [
        "kitty/kitty.conf"
        "mako/config"
        "waybar/config"
        "waybar/style.css"
      ] (_: {onChange = lib.mkForce "";});
    })];
    # Adopt the paths already used by the installed shell, session and Firefox wrapper.
    home-manager.users.tenzyu.local.homeMigration.adoptedRoutes = {
      bash-history = "intended";
      bun = "intended";
      claude = "intended";
      codex = "intended";
      firefox = "intended";
      gemini = "intended";
      node-history = "intended";
      npm = "intended";
      rust = "intended";
      zsh = "intended";
    };

    # This key permits the neko7 -> neko5 SSH path only.
    # Generic SSH enablement must not grant access to other hosts.
    users.users.tenzyu.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeiSmoim2RKyd6smA5t86Pr7Lt+nOF1oXEHQjsw74O5 neko7-to-neko5"
    ];

    # Jay is the normal neko5 generation. Only Gamescope is an alternative
    # native DRM session. Keep the old Hyprland modules in the repository.
    imports = [
      ({...}: {
        specialisation.neko5-gamescope.configuration = {lib, ...}: {
          neko5Experiment.compositor = lib.mkForce "gamescope";
        };
      })
    ];
    neko5Experiment.compositor = "jay";
    home-manager.users.tenzyu.xdg.configFile = {
      "waybar/config".enable = false;
      "waybar/style.css".enable = false;
    };

    local = {
      context = {
        flakePath = "/home/tenzyu/.nixfiles";
        systemStateVersion = "26.05";
      };
      features = {
        neko5-hardware.enable = true;
        laptop-input.enable = true;

        kernel-latest.enable = true;
        systemd-boot.enable = true;
        zsh.enable = true;

        time.enable = true;
        locale.enable = true;
        fonts.enable = true;

        nix.enable = true;
        nix-store-clean.enable = true;
        nix-remote-client.enable = true;
        stub-ld.enable = true;

        networkmanager.enable = true;
        nsncd-resolver-lifecycle.enable = true;
        ssh.enable = true;
        sops-nix.enable = true;
        tailscale.enable = true;

        pipewire.enable = true;
        udiskie.enable = true;
        fcitx5.enable = true;

        intel-graphics.enable = true;
        wayland-session.enable = false;
        neko5-slim-desktop.enable = true;
        hyprland-core.enable = false;
        hyprland-tenzyu.enable = false;
        desktop-performance.enable = true;
        gaming-mouse.enable = true;
        open-tablet-driver.enable = true;
        otd-access.enable = true; # for flash custom firmware
        neko5-osu-first.enable = true;

        # NOTE: Under configuration.
        splitcast-capture.enable = false;

        docker-rootless.enable = false;
        hyprlock.enable = false;
        waydroid.enable = false;
        bluetooth.enable = false;
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
        networkmanager-access.enable = true;
        nix-access.enable = true;
        catppuccin.enable = true;
        zsh.enable = true;
        nh.enable = true;
        nix-tools.enable = true;
        git-tools.enable = true;
        disk-tools.enable = true;
        herdr.enable = true;

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

        kitty.enable = true;
        rofi.enable = true;
        waybar.enable = false;
        mako.enable = true;
        wlogout.enable = true;
        hyprpaper.enable = false;
        packages-desktop.enable = true;
        firefox.enable = true;
        chromium.enable = true;
        zed-editor.enable = false;
        hyprland-tenzyu.enable = false;
        hyprland-core.enable = false;
        obsidian.enable = true;
        osu-lazer.enable = true;
        neko5-osu-first.enable = false;
        parsec.enable = true;
        dolphin.enable = true;
        steam.enable = true;
        discord.enable = true;
        prismlauncher.enable = true;

        # TODO: migration scripts are buggy right now.
        home-layout.enable = true;

        # NOTE: under construction.
        splitcast-capture.enable = false;

        # NOTE: it's running on neko7 now.
        opencode.enable = false;
        rtk.enable = false;

        codex.enable = false;
        onair.enable = false;
        llmproxy.enable = false;
        castalia.enable = false;
        android-mic.enable = false;
      };
    };
  };
}
