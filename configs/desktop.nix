{
  lib,
  pkgs,
  ...
}:
with lib; {
  # Wayland configuration
  programs.hyprland = {
    enable = mkDefault true;
    xwayland.enable = mkDefault true;
  };

  # Wayland packages
  environment.systemPackages = with pkgs; [
    # Wayland compositor and utilities
    hyprland
    waybar
    swaybg
    swaylock
    wl-clipboard
    wofi
    mako

    # Basic desktop utilities
    firefox
    alacritty
    rofi-wayland
    feh
    dunst

    # Media
    vlc
    gimp
    inkscape

    # Development
    vscode
    jetbrains.idea-community
  ];

  # Audio configuration
  security.rtkit.enable = mkDefault true;
  services.pipewire = {
    enable = mkDefault true;
    alsa.enable = mkDefault true;
    alsa.support32Bit = mkDefault true;
    pulse.enable = mkDefault true;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = mkDefault true;
    powerOnBoot = mkDefault true;
  };

  # Desktop services
  services = {
    printing.enable = mkDefault true;
    blueman.enable = mkDefault true;
    gvfs.enable = mkDefault true;
  };

  # Fonts
  fonts = {
    enableDefaultPackages = mkDefault true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      font-awesome
      source-han-sans
      source-han-serif
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
}
