{
  lib,
  pkgs,
  hostname,
  username,
  ...
}: let
  configsPath = ../profiles/${hostname}/configurations.nix;
in
  with lib; {
    # System
    imports =
      [
        ../profiles/${hostname}/hardware-configuration.nix
      ]
      ++ lib.optional (lib.pathExists configPath) configPath;

    # Users
    users.users.${username} = {
      isNormalUser = mkDefault true;
      shell = mkDefault pkgs.zsh;
      extraGroups = mkDefault ["wheel"];
    };
    home-manager.users.${username} = {
      imports = [
        ../hosts/${hostname}/${username}.nix
        {
          programs.home-manager.enable = mkDefault true;
          xdg.enable = mkDefault true;
          home.preferXdgDirectories = mkDefault true;
          home.username = mkDefault "${username}";
          home.homeDirectory = mkDefault "/home/${username}";
          home.stateVersion = "24.11";
        }
      ];
    };

    # Shells
    programs.zsh.enable = mkDefault true;
    environment.pathsToLink = mkDefault ["/share/zsh"];
    environment.shells = mkDefault [pkgs.zsh];
    environment.enableAllTerminfo = mkDefault true;

    # Networks
    time.timeZone = mkDefault "Asia/Tokyo";
    networking.hostName = mkDefault "${hostname}";
    networking.networkmanager.enable = mkDefault true; # Easiest to use and most distros use this by default.
    services.openssh.enable = mkDefault true;

    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = mkDefault true;
    boot.loader.efi.canTouchEfiVariables = mkDefault true;

    # Wayland
    programs.hyprland = {
      enable = mkDefault true;
      xwayland.enable = mkDefault true;
    };
    programs.hyprlock.enable = mkDefault true;

    # Audio configuration
    services.pipewire = {
      enable = mkDefault true;
      pulse.enable = mkDefault true;
    };

    # Bluetooth
    services.blueman.enable = mkDefault true;
    hardware.bluetooth = {
      enable = mkDefault true;
      powerOnBoot = mkDefault true;
    };

    # Fonts
    fonts = {
      enableDefaultPackages = mkDefault true;
      packages = with pkgs; [
        fira-code
        fira-code-symbols
        fira-code-nerdfont
        font-awesome
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
    };

    # Environment variables for Wayland
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      GDK_BACKEND = "wayland";
      WLR_NO_HARDWARE_CURSORS = "1";
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "Hyprland";
    };

    i18n.defaultLocale = mkDefault "en_US.UTF-8";
    i18n.inputMethod = {
      enable = mkDefault true;
      type = mkDefault "fcitx5";
      fcitx5.waylandFrontend = mkDefault true;
      fcitx5.addons = [
        pkgs.fcitx5-mozc-ut
      ];
    };

    console = {
      font = mkDefault "Lat2-Terminus16";
      # keyMap = "us";
      # useXkbConfig = true; # use xkb.options in tty.
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
    system.stateVersion = "24.11"; # Did you read the comment?
  }
