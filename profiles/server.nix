{
  lib,
  pkgs,
  hostname,
  username,
  ...
}: let
  configPath = ../hosts/${hostname}/configuration.nix;
in
  with lib; {
    imports =
      [
        ../hosts/${hostname}/hardware-configuration.nix
      ]
      ++ lib.optional (lib.pathExists configPath) configPath;

    # Bootloader.
    boot.loader.grub.enable = true;
    boot.loader.grub.device = "/dev/sda";
    boot.loader.grub.useOSProber = true;
    # Use latest kernel.
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Set your time zone.
    time.timeZone = mkDefault "Asia/Tokyo";
    # Network.
    networking.hostName = mkDefault "${hostname}";
    networking.networkmanager.enable = true;
    services.openssh = {
      enable = mkDefault true;
      settings = {
        PasswordAuthentication = mkDefault false;
        KbdInteractiveAuthentication = mkDefault false;
        GatewayPorts = mkDefault "yes";
      };
    };

    # Users
    users.users.${username} = {
      isNormalUser = mkDefault true;
      shell = pkgs.zsh;
      extraGroups = ["networkmanager" "wheel"];
    };
    home-manager.users.${username} = {
      imports = [
        ../hosts/${hostname}/${username}.nix
        {
          programs.home-manager.enable = mkDefault true;
          xdg.enable = mkDefault true;
          home.username = mkDefault "${username}";
          home.homeDirectory = mkDefault "/home/${username}";
          home.stateVersion = "25.11";
        }
      ];
    };

    # Shells
    programs.zsh.enable = mkDefault true;
    environment.pathsToLink = mkDefault ["/share/zsh"];
    environment.shells = mkDefault [pkgs.zsh];
    environment.enableAllTerminfo = mkDefault true;

    # Select internationalisation properties.
    i18n.defaultLocale = mkDefault "en_US.UTF-8";
    i18n.extraLocaleSettings = mkDefault {
      LC_ADDRESS = "ja_JP.UTF-8";
      LC_IDENTIFICATION = "ja_JP.UTF-8";
      LC_MEASUREMENT = "ja_JP.UTF-8";
      LC_MONETARY = "ja_JP.UTF-8";
      LC_NAME = "ja_JP.UTF-8";
      LC_NUMERIC = "ja_JP.UTF-8";
      LC_PAPER = "ja_JP.UTF-8";
      LC_TELEPHONE = "ja_JP.UTF-8";
      LC_TIME = "ja_JP.UTF-8";
    };

    # Configure keymap in X11.
    services.xserver.xkb = mkDefault {
      layout = "us";
      variant = "";
    };

    # Fonts.
    fonts = {
      enableDefaultPackages = mkDefault true;
      packages = with pkgs; [
        fira-code
        fira-code-symbols
        nerd-fonts.fira-code
        font-awesome
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
    };
    console = {
      font = mkDefault "Lat2-Terminus16";
    };

    # This option defines the first version of NixOS you have installed on this particular machine,
    # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
    #
    # Most users should NEVER change this value after the initial install, for any reason,
    # even if you've upgraded your system to a new NixOS release.
    #
    # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
    # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
    # to actually do that.
    #
    # This value being lower than the current NixOS release does NOT mean your system is
    # out of date, out of support, or vulnerable.
    #
    # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
    # and migrated your data accordingly.
    #
    # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
    system.stateVersion = "25.11"; # Did you read the comment?
  }
