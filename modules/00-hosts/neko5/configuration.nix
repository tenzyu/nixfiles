{
  configurations.nixos.neko5.module = {
    home-manager.users.tenzyu.local.features.splitcast-capture.settings.peer.ssh_host = "neko7";

    local.context.flakePath = "/home/tenzyu/.nixfiles";

    local.features = {
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
      ssh.enable = true;
      tailscale.enable = true;

      pipewire.enable = true;
      udiskie.enable = true;
      fcitx5.enable = true;

      intel-graphics.enable = true;
      wayland-session.enable = true;
      desktop-performance.enable = true;
      gaming-mouse.enable = true;
      open-tablet-driver.enable = true;

      # NOTE: Under configuration.
      splitcast-capture.enable = false;

      docker-rootless.enable = false;
      hyprlock.enable = false;
      waydroid.enable = false;
      bluetooth.enable = false;
    };

    local.users.tenzyu = {
      enable = true;
      isAdmin = true;
      homeStateVersion = "26.05";
      email = "tenzyu.on@gmail.com";
      homeDirectory = "/home/tenzyu";

      features = {
        networkmanager-access.enable = true;
        nix-access.enable = true;
        catppuccin.enable = true;
        zsh.enable = true;
        nix-tools.enable = true;
        git-tools.enable = true;
        disk-tools.enable = true;
        herdr.enable = true;

        tenzyu-desktop.enable = true;
        hyprland-tenzyu.enable = true;
        hyprland-gaming-mode.enable = true;
        obsidian.enable = true;
        osu-lazer.enable = true;
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
