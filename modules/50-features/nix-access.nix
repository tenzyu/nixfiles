{
  flake.features.nix-access = {
    projections.homeManager.payload = {...}: {};

    joins.userToNixos.payload = {
      lib,
      user,
      ...
    }: {
      nix.settings.trusted-users = lib.mkAfter [user.name];
    };
  };
}
