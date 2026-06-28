{config, ...}: {
  flake.features.stub-ld.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    environment.stub-ld.enable = true;
    programs.nix-ld.enable = true;
  };
}
