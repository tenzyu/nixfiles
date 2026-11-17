{
  lib,
  nixosModules,
  usersLib,
}: rec {
  userSeededNixosFeaturesModule = {
    config,
    lib,
    ...
  }: let
    users = usersLib.enabledUsers config.local.users;

    enabledUserFeatureNames = lib.unique (
      lib.concatMap
      (
        user:
          lib.attrNames (
            lib.filterAttrs (_name: feature: feature.enable or false) user.features
          )
      )
      (lib.attrValues users)
    );

    names = lib.filter (name: builtins.hasAttr name nixosModules) enabledUserFeatureNames;
  in {
    config = {
      local.features = lib.genAttrs names (_name: {
        enable = lib.mkDefault true;
      });
      assertions = map (name: {
        assertion = config.local.features.${name}.enable;
        message = ''
          A Home Manager user enabled feature '${name}', but its NixOS
          counterpart is disabled. Enable local.features.${name} on the host
          or disable the user feature; a partial projection is not supported.
        '';
      }) names;
    };
  };

  nixosUserAccountsModule = {
    config,
    lib,
    ...
  }: let
    users = usersLib.enabledUsers config.local.users;
  in {
    config = {
      users.groups =
        lib.mapAttrs (_name: _user: {}) users;

      users.users =
        lib.mapAttrs (name: user: {
          isNormalUser = lib.mkDefault true;
          group = name;
          home = user.homeDirectory;

          extraGroups = lib.mkAfter (lib.optional user.isAdmin "wheel");
        })
        users;
    };
  };
}
