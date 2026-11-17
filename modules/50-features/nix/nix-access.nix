{
  flake.modules.nixos.nix-access = {
    config,
    helpers,
    lib,
    ...
  }: {
    config.nix.settings.trusted-users =
      lib.mkAfter (helpers.userNamesWithFeature "nix-access" config);
  };

  flake.modules.homeManager.nix-access = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.nix-access.enable {};
  };
}
