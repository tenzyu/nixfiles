{
  flake.modules.nixos.docker-user-access = {
    config,
    helpers,
    lib,
    ...
  }: {
    config.users.users =
      helpers.mapUsersWithFeature "docker-user-access" config
      (name: _user: {
        extraGroups = lib.mkAfter ["docker"];
      });
  };

  flake.modules.homeManager.docker-user-access = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.docker-user-access.enable {};
  };
}
