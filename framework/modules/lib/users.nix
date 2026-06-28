{
  lib,
  featuresLib,
}: rec {
  enabledUsers = users:
    lib.filterAttrs (_name: user: (user.enable or true) != false) users;

  compactNixosUsers = users:
    lib.mapAttrs (name: user: {
      enable = user.enable;
      isAdmin = user.isAdmin;
      email = user.email;
      homeDirectory = user.homeDirectory;
      homeStateVersion = user.homeStateVersion;
      features = featuresLib.compactFeatureSet user.features;
    })
    users;
}
