{
  lib,
  pkgs,
  ...
}:
with lib; {
  # Basic system configuration
  time.timeZone = mkDefault "Asia/Tokyo";
  i18n.defaultLocale = mkDefault "en_US.UTF-8";

  # Basic security
  security.sudo.wheelNeedsPassword = mkDefault false;
  services.openssh.enable = mkDefault true;

  # Basic networking
  networking.networkmanager.enable = mkDefault true;

  # Basic user configuration
  users.users = {
    root = {
      hashedPassword = mkDefault null; # Disable root password
    };
  };

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
  ];

  # Basic system services
  services = {
    dbus.enable = mkDefault true;
    avahi.enable = mkDefault true;
  };

  # Basic hardware support
  hardware.enableRedistributableFirmware = mkDefault true;
}
