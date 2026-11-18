{
  lib,
  features,
}: rec {
  usersWithFeature = feature: cfg:
    lib.filterAttrs
    (_name: user:
      (user.enable or true)
      && features.featureEnabled feature (user.features or {}))
    cfg.local.users;

  userNamesWithFeature = feature: cfg:
    lib.attrNames (usersWithFeature feature cfg);

  mapUsersWithFeature = feature: cfg: f:
    lib.mapAttrs f (usersWithFeature feature cfg);
}
