# Server profile — inherits shared base, adds server-specific config.
{
  lib,
  pkgs,
  hostname,
  ...
}: let
  configPath = ../../hosts/${hostname}/configuration.nix;
in
  with lib; {
    imports =
      [
        ./shared.nix
        ../../hosts/${hostname}/hardware-configuration.nix
      ]
      ++ lib.optional (lib.pathExists configPath) configPath;

    # Boot (server uses GRUB)
    boot.loader.grub.enable = true;
    boot.loader.grub.device = "/dev/sda";
    boot.loader.grub.useOSProber = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # Network
    networking.networkmanager.enable = true;

    # i18n (Japanese locale)
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

    # Keymap
    services.xserver.xkb = mkDefault {
      layout = "us";
      variant = "";
    };

    # Fonts
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
  }
