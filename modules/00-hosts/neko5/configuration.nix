{
  configurations.nixos.neko5.module = {
    home-manager.users.tenzyu.local.features.splitcast-capture.settings.peer.ssh_host = "neko7";

    local.context.flakePath = "/home/tenzyu/.nixfiles";

    local.features = {
      neko5-hardware.enable = true;
      nix.enable = true;
      nix-store-clean.enable = true;
      zsh.enable = true;
      time.enable = true;
      locale.enable = true;
      ssh.enable = true;
      tailscale.enable = true;
      systemd-boot.enable = true;
      pipewire.enable = true;
      splitcast-capture.enable = true;
      bluetooth.enable = true;
      intel-graphics.enable = true;
      fcitx5.enable = true;
      kernel-latest.enable = true;
      udiskie.enable = true;
      open-tablet-driver.enable = true;
      stub-ld.enable = true;
      laptop-input.enable = true;
      fonts.enable = true;
      desktop-performance.enable = true;
      wayland-session.enable = true;
      networkmanager.enable = true;
      gaming-mouse.enable = true;
      nix-remote-client.enable = true;

      docker-rootless.enable = false;
      hyprlock.enable = false;
      waydroid.enable = false;
    };

    local.users.tenzyu = {
      enable = true;
      isAdmin = true;
      homeStateVersion = "26.05";
      email = "tenzyu.on@gmail.com";
      homeDirectory = "/home/tenzyu";

      features = {
        splitcast-capture.enable = true;
        tenzyu-desktop.enable = true;
        hyprland-tenzyu.enable = true;
        hyprland-gaming-mode.enable = true;
        steam.enable = true;
        discord.enable = true;
        prismlauncher.enable = true;
        home-layout.enable = true;

        opencode.enable = true;
        rtk.enable = true;

        obsidian.enable = true;
        osu-lazer.enable = true;
        parsec.enable = true;
        networkmanager-access.enable = true;
        nix-access.enable = true;
        catppuccin.enable = true;
        dolphin.enable = true;
        zsh.enable = true;
        nix-tools.enable = true;
        git-tools.enable = true;
        disk-tools.enable = true;
        herdr.enable = true;

        codex.enable = false;
        onair.enable = false;
        llmproxy.enable = false;
        castalia.enable = false;
        android-mic.enable = false;
      };
    };
  };
}
