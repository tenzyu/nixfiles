{
  lib,
  nixosFeatureNames,
  homeFeatureNames,
  featuresLib,
}: let
  inherit (lib) mkOption types;

  nullable = type:
    mkOption {
      type = types.nullOr type;
      default = null;
    };

  context = {
    flakePath = nullable types.str;
    hostName = nullable types.str;
    nixosConfigurationName = nullable types.str;
  };

  homeContext = {
    homeConfigurationName = mkOption {
      type = types.str;
    };
    embeddedInNixOS = mkOption {
      type = types.bool;
      default = false;
    };
  };

  homeUser = {
    name = mkOption {
      type = types.str;
    };
    email = mkOption {
      type = types.str;
      default = "";
    };
    homeDirectory = mkOption {
      type = types.str;
    };
    stateVersion = mkOption {
      type = types.str;
      default = "26.05";
    };
  };

  nixosOptions = featureOptions: {
    inherit context;
    features = featureOptions nixosFeatureNames;

    users = mkOption {
      default = {};
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
          };
          isAdmin = mkOption {
            type = types.bool;
            default = false;
          };
          email = mkOption {
            type = types.str;
            default = "";
          };
          homeDirectory = mkOption {
            type = types.str;
            default = "/home/${name}";
          };
          homeStateVersion = mkOption {
            type = types.str;
            default = "26.05";
          };
          features = featureOptions homeFeatureNames;
        };
      }));
    };
  };

  # Keep local.* visible in debug.options for nixd and accept direct target options.
  seedModuleType = localOptions:
    types.submodule {
      freeformType = types.attrsOf types.anything;
      options.local = localOptions;
    };
in {
  nixosFeatureOptionsModule.options.local = nixosOptions featuresLib.actualFeatureOptions;

  homeFeatureOptionsModule.options.local = {
    user = homeUser;
    context = context // homeContext;
    features = featuresLib.actualFeatureOptions homeFeatureNames;
  };

  nixosConfigurationModuleType = seedModuleType (nixosOptions featuresLib.seedFeatureOptions);

  homeConfigurationModuleType = seedModuleType {
    user =
      homeUser
      // {
        name = nullable homeUser.name.type;
        homeDirectory = nullable homeUser.homeDirectory.type;
      };
    context =
      context
      // homeContext
      // {
        homeConfigurationName = nullable homeContext.homeConfigurationName.type;
      };
    features = featuresLib.seedFeatureOptions homeFeatureNames;
  };
}
