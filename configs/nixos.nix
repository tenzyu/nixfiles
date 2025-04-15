{
  inputs,
  pkgs,
  config,
  lib,
  username,
  hostname,
  ...
}: {
  time.timeZone = "Asia/Tokyo";
  networking.hostName = "${hostname}";

  programs.zsh.enable = true;
  environment.pathsToLink = ["/share/zsh"];
  environment.shells = [pkgs.zsh];
  environment.enableAllTerminfo = true;

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ["wheel"];
  };

  system.stateVersion = "24.11";

  home-manager.users.${username} = {
    imports = [
      ./profiles/${hostname}/${username}.nix
    ];
  };

  nix = {
    settings = {
      trusted-users = [username];
      accept-flake-config = true;
      auto-optimise-store = true;
    };

    registry = {
      nixpkgs = {
        flake = inputs.nixpkgs;
      };
    };

    nixPath = [
      "nixpkgs=${inputs.nixpkgs.outPath}"
      "nixos-config=/etc/nixos/configuration.nix"
      "/nix/var/nix/profiles/per-user/root/channels"
    ];

    package = pkgs.nixVersions.stable;
    extraOptions = ''experimental-features = nix-command flakes'';

    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };
  };

  # Additional configurations from neko5
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  services.blueman.enable = true;
  services.libinput.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = [
      pkgs.fcitx5-mozc-ut
    ];
  };

  console = {
    font = "Lat2-Terminus16";
  };
}
