{...}: {
  flake.features.udiskie.projections.nixos.payload = {
    pkgs,
    ...
  }: {
    environment.systemPackages = [pkgs.udiskie];

    services.udisks2.enable = true;
  };
}
