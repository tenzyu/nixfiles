{
  configurations.nixos.neko5.module = {
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

    # Physical panel and personal application bindings, not generic Jay defaults.
    home-manager.users.tenzyu.local.jay = {
      output = {
        connector = "eDP-1";
        width = 1366;
        height = 768;
        scale = 1.0;
        # osu! EGL did not request tearing; variant3 stayed at 60 sync flips/s.
        # Variant2 + osu!-scoped noccs sustained 480 async flips/s on this panel.
        # Other fullscreen apps may fall back to sync if their buffers are incompatible.
        tearingMode = "variant2";
      };
      shortcuts = {
        logo-b = ''{ type = "exec", exec = "firefox" }'';
        logo-o = ''{ type = "exec", exec = "osu-lazer" }'';
      };
    };
    # Preserve direct scanout while avoiding the Gen9 CCS async-flip rejection.
    home-manager.users.tenzyu.local.osuLazer.disableIntelCcs = true;

    # Firefox 149+ prefers the XDG portal file picker. Bypass only this
    # interface on native Firefox; leave ScreenCast and other portals intact.
    # Mozilla bug 1982187 describes the same missing-dialog symptom.
    home-manager.users.tenzyu.programs.firefox.policies.Preferences."widget.use-xdg-desktop-portal.file-picker" = {
      Value = 0;
      Status = "default";
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
        fileman.enable = false;
        thunar.enable = true;
        fcitx5.enable = true;

        intel-graphics.enable = true;
        wayland-session.enable = false;
        jay.enable = true;
        hyprland-core.enable = false;
        hyprland-tenzyu.enable = false;
        desktop-performance.enable = true;
        gaming-mouse.enable = true;
        open-tablet-driver.enable = true;
        otd-access.enable = true; # for flash custom firmware

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
        dua.enable = true;
        git-tools.enable = true;
        gitui.enable = true;
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

        jay.enable = true;
        kitty.enable = false;
        # Foot uses Wayland shared-memory rendering, not a second GPU renderer.
        # Retain Alacritty as the selectable rollback terminal, not a daemon.
        alacritty.enable = false;
        foot.enable = true;
        # Restore the stock Wayland-capable launcher after intermittent Tofi startup.
        rofi.enable = true;
        tofi.enable = false;
        cclip.enable = true;
        waybar.enable = false;
        mako.enable = true;
        wlogout.enable = true;
        hyprpaper.enable = false;
        # Select capability owners independently, not the legacy desktop bundle.
        packages-desktop.enable = false;
        desktop-tools.enable = true;
        obs-studio.enable = true;
        easyeffects.enable = true;
        firefox.enable = true;
        chromium.enable = true;
        zed-editor.enable = false;
        hyprland-tenzyu.enable = false;
        hyprland-core.enable = false;
        obsidian.enable = true;
        osu-lazer.enable = true;
        neko5-osu-first.enable = false;
        parsec.enable = true;
        dolphin.enable = false;
        fileman.enable = false;
        thunar.enable = true;
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
