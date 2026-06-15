{
  config,
  ...
}: {
  flake.modules.nixos.empty-nix-access-tokens = {config, lib, ...}: {
    config = lib.mkIf config.local.features.empty-nix-access-tokens.enable {
      nix.settings.access-tokens = [];
    };
  };
}
