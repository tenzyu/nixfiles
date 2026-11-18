{
  lib,
  featuresLib,
}: rec {
  enabledUsers = users:
    lib.filterAttrs (_name: user: user.enable or true) users;

  compactNixosUsers = users:
    lib.mapAttrs (name: user: {
      inherit (user) enable context;
      features = featuresLib.compactFeatureSet user.features;
    })
    users;
}
