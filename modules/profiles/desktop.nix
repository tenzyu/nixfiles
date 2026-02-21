# Desktop profile — inherits shared base, adds desktop-specific config.
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

    # Boot
    boot.loader.systemd-boot.enable = mkDefault true;
    boot.loader.efi.canTouchEfiVariables = mkDefault true;

    # Network
    networking.networkmanager.enable = mkDefault true;

    # Audio
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
        nerd-fonts.fira-code
        font-awesome
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
    };

    # Wayland
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

    # Input method
    i18n.inputMethod = {
      enable = mkDefault true;
      type = mkDefault "fcitx5";
      fcitx5.waylandFrontend = mkDefault true;
      fcitx5.addons = [
        pkgs.fcitx5-mozc-ut
      ];
    };
  }
