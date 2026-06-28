{config, ...}: {
  flake.features.nix-ld.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    programs.nix-ld.enable = true;
  };
}
