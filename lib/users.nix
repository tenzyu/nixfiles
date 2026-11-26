{
  lib,
  features,
}: rec {
  enabledUsers = users:
    lib.filterAttrs (_name: user: user.enable or true) users;

  usersWithFeature = feature: cfg:
    lib.filterAttrs
    (_name: user: features.featureEnabled feature (user.features or {}))
    (enabledUsers cfg.local.users);

  userNamesWithFeature = feature: cfg:
    lib.attrNames (usersWithFeature feature cfg);

  mapUsersWithFeature = feature: cfg: f:
    lib.mapAttrs f (usersWithFeature feature cfg);
}
