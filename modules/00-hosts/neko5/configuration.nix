{
  configurations.nixos.neko5.module = {
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
      bluetooth.enable = true;
      intel-graphics.enable = true;
      docker-rootless.enable = true;
      fcitx5.enable = true;
      kernel-latest.enable = true;
      udiskie.enable = true;
      hyprlock.enable = true;
      open-tablet-driver.enable = true;
      stub-ld.enable = true;
      laptop-input.enable = true;
      fonts.enable = true;
      desktop-performance.enable = true;
      wayland-session.enable = true;
      networkmanager.enable = true;
    };

    local.users.tenzyu = {
      enable = true;
      isAdmin = true;
      homeStateVersion = "26.05";
      email = "tenzyu.on@gmail.com";
      homeDirectory = "/home/tenzyu";

      features = {
        tenzyu-desktop.enable = true;
        hyprland-tenzyu.enable = true;
        hyprland-gaming-mode.enable = true;
        steam.enable = true;
        android-mic.enable = true;
        discord.enable = true;
        prismlauncher.enable = true;
        codex.enable = true;
        opencode.enable = true;
        obsidian.enable = true;
        osu-lazer.enable = true;
        parsec.enable = true;
        networkmanager-access.enable = true;
        nix-access.enable = true;
        rtk.enable = true;
        catppuccin.enable = true;
        dolphin.enable = true;
        zsh.enable = true;
        nix-tools.enable = true;
        git-tools.enable = true;
        disk-tools.enable = true;
        castalia.enable = true;
        onair.enable = true;
        herdr.enable = true;
      };
    };
  };
}
