{
  flake.modules.nixos.networkmanager-access = {
    config,
    helpers,
    lib,
    ...
  }: {
    config.users.users =
      helpers.mapUsersWithFeature "networkmanager-access" config
      (name: _user: {
        extraGroups = lib.mkAfter ["networkmanager"];
      });
  };

  flake.modules.homeManager.networkmanager-access = {};
}
