{
  flake.modules.nixos.wsl-default-user = {
    config,
    helpers,
    lib,
    ...
  }: let
    names = helpers.userNamesWithFeature "wsl-default-user" config;
  in {
    config = lib.mkIf (names != []) {
      assertions = [
        {
          assertion = lib.length names == 1;
          message = "Exactly one local user may enable local.users.<name>.features.wsl-default-user.enable.";
        }
      ];

      wsl.defaultUser = lib.mkDefault (lib.head names);
    };
  };

  flake.modules.homeManager.wsl-default-user = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.wsl-default-user.enable {};
  };
}
