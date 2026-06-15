{ feature, ... }: {
  configurations.nixos.neko7.module = {
    imports = [
      (feature.system {
        stateVersion = "26.05";
        features = {
          neko7-hardware = true;
          nix = true;
          zsh = true;
          time = true;
          locale = true;
          ssh = true;
          tailscale = true;
          resolvconf-blacklist-gateway = true;
          disable-ipv6 = true;
          systemd-boot = true;
          proxmox-guest = true;
          nvidia-graphics = true;
          kernel-latest = true;
          networkmanager = true;
          ja-extra-locales = true;
          us-xserver-keyboard = true;
          fonts = true;
          stub-ld = true;
          nix-ld = true;
          docker-rootless = true;
          llama-cpp-cuda = true;
        };
      })

      (feature.users {
        tenzyu = {
          isAdmin = true;
          homeStateVersion = "26.05";
          fullName = "tenzyu";
          email = "tenzyu.on@gmail.com";

          features = {
            tenzyu-cli = true;
            catppuccin = true;
            nix-access = true;
          };

          imports = [
            ({ pkgs, ... }: {
              home.packages = with pkgs; [
                nh
                jq
                jqp
                lazygit
                zip
                ncdu
                crosspipe
              ];
            })
          ];
        };
      })
    ];
  };
}
