{
  config,
  ...
}: {
  flake.modules.nixos.nix-ld = {config, lib, ...}: {
    config = lib.mkIf config.local.features.nix-ld.enable {
      programs.nix-ld.enable = true;
    };
  };
}
