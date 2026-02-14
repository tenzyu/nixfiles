{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.udiskie
  ];

  # runtime dependencies
  services.udisks2 = {
    enable = true;
  };
}
