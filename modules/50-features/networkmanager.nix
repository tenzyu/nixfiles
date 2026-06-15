{
  flake.modules.nixos.networkmanager = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.networkmanager.enable {
      networking.networkmanager.enable = true;

      networking.nameservers = [
        "1.1.1.1"
        "1.0.0.1"
        "8.8.8.8"
        "8.8.4.4"
      ];
    };
  };

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

  flake.modules.homeManager.networkmanager-access = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.networkmanager-access.enable {};
  };
}
