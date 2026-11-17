{config, ...}: {
  flake.modules.nixos.stub-ld = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.stub-ld.enable {
      environment.stub-ld.enable = true;
      programs.nix-ld.enable = true;
    };
  };
}
