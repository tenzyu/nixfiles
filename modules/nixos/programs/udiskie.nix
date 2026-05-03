{...}: {
  flake.modules.nixos.udiskie = {pkgs, ...}: {
    environment.systemPackages = [
      pkgs.udiskie
    ];

    services.udisks2.enable = true;
  };
}
