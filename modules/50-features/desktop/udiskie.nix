{...}: {
  flake.modules.nixos.udiskie = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.udiskie.enable {
      environment.systemPackages = [pkgs.udiskie];

      services.udisks2.enable = true;
    };
  };
}
