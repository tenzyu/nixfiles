{
  homeFeatureOptionsModule,
  homeModuleList,
  embeddedHomeFeatures,
  enabledUsers,
}: selectedUsers: {
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
                inherit (user.context) email homeDirectory;
                stateVersion = user.context.homeStateVersion;
              };

              local.context = {
                flakePath = config.local.context.flakePath;
                hostName = config.local.context.hostName;
                nixosConfigurationName = config.local.context.nixosConfigurationName;
                homeConfigurationName = "${userName}@${config.local.context.nixosConfigurationName}";
                embeddedInNixOS = true;
              };

              # Respect host explicit false without converting implicit native false into
               # an HM false definition.
               local.features =
                 embeddedHomeFeatures
                   (selectedUsers.${userName}.features or {})
                   user.features;

              programs.home-manager.enable = lib.mkDefault true;
              xdg.enable = lib.mkDefault true;
              home.preferXdgDirectories = lib.mkDefault true;
              home.username = lib.mkDefault userName;
              home.homeDirectory = lib.mkDefault user.context.homeDirectory;
              home.stateVersion = lib.mkDefault user.context.homeStateVersion;
            }
          ];
        }
      )
      (enabledUsers config.local.users);
  };
}
