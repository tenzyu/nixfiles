{lib, ...}: {
  config.flake.lib.helpers = rec {
    usersWithFeature = feature: cfg:
      lib.filterAttrs
      (_name: user:
        (user.enable or true)
        && (user.features.${feature}.enable or false))
      cfg.local.users;

    userNamesWithFeature = feature: cfg:
      lib.attrNames (usersWithFeature feature cfg);

    mapUsersWithFeature = feature: cfg: f:
      lib.mapAttrs f (usersWithFeature feature cfg);
  };
}
