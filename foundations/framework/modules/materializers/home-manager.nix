{
  lib,
  homeFeatureOptionsModule,
  nixpkgsPolicyModule,
  homeModuleList,
  enabledFeatures,
  enabledUsers,
  helpers,
}: {
  hmFactoryModule = {
    config,
    lib,
    helpers,
    ...
  }: {
    config.home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";

      extraSpecialArgs = {
        inherit helpers;
      };

      sharedModules =
        [
          homeFeatureOptionsModule
        ]
        ++ homeModuleList;

      users =
        lib.mapAttrs
        (
          userName: user: {
            imports = [
              {
                local.user = {
                  name = userName;
                  email = user.email;
                  homeDirectory = user.homeDirectory;
                  stateVersion = user.homeStateVersion;
                };

                local.context = {
                  flakePath = config.local.context.flakePath;
                  hostName = config.local.context.hostName;
                  nixosConfigurationName = config.local.context.nixosConfigurationName;
                  homeConfigurationName = "${userName}@${config.local.context.nixosConfigurationName}";
                  embeddedInNixOS = true;
                };

                local.features = enabledFeatures user.features;

                programs.home-manager.enable = lib.mkDefault true;
                xdg.enable = lib.mkDefault true;
                home.preferXdgDirectories = lib.mkDefault true;
                home.username = lib.mkDefault userName;
                home.homeDirectory = lib.mkDefault user.homeDirectory;
                home.stateVersion = lib.mkDefault user.homeStateVersion;
              }
            ];
          }
        )
        (enabledUsers config.local.users);
    };
  };
}
