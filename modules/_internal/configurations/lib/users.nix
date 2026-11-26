{
  lib,
  featuresLib,
}: rec {
  inherit (import ../../../../lib/users.nix {
    inherit lib;
    features = import ../../../../lib/features.nix {inherit lib;};
  }) enabledUsers;

  compactNixosUsers = users:
    lib.mapAttrs (name: user: {
      inherit (user) enable context;
      features = featuresLib.compactFeatureSet user.features;
    })
    users;
}
