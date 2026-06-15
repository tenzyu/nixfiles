{
  feature,
  inputs,
  ...
}: {
  configurations.nixos.neko5.module = {
    imports = [
      (feature.system {
        stateVersion = "26.05";
        features = {
          neko5-hardware = true;
          nix = true;
          nix-store-clean = true;
          zsh = true;
          time = true;
          locale = true;
          ssh = true;
          tailscale = true;
          systemd-boot = true;
          pipewire = true;
          bluetooth = true;
          intel-graphics = true;
          docker-rootless = true;
          fcitx5 = true;
          kernel-latest = true;
          udiskie = true;
          hyprlock = true;
          open-tablet-driver = true;
          stub-ld = true;
          laptop-input = true;
          fonts = true;
          desktop-performance = true;
          wayland-session = true;
        };
      })

      (feature.users {
        tenzyu = {
          isAdmin = true;
          homeStateVersion = "26.05";
          fullName = "tenzyu";
          email = "tenzyu.on@gmail.com";

          features = {
            tenzyu-desktop = true;
            hyprland-tenzyu = true;
            hyprland-gaming-mode = true;
            steam = true;
            android-mic = true;
            discord = true;
            prismlauncher = true;
            codex = true;
            opencode = true;
            obsidian = true;
            osu-lazer = true;
            parsec = true;
            networkmanager-access = true;
            nix-access = true;
            rtk = true;
            catppuccin = true;
            dolphin = true;
          };

          imports = [
            ({pkgs, ...}: {
              home.packages = with pkgs; [
                nh
                jq
                jqp
                lazygit
                zip
                ncdu
                crosspipe
                gh
                qdirstat
                inputs.castalia.packages.${pkgs.system}.castalia
                inputs.onair.packages.${pkgs.system}.default
              ];
            })
          ];
        };
      })
    ];
  };
}
