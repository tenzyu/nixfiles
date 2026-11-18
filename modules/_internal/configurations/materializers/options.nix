{
  lib,
  nixosFeatureNames,
  homeFeatureNames,
  featuresLib,
  composition,
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
    context = (composition.namedDisjoint {
      label = "nixos-context-options";
      layers = [
        {name = "shared-context"; attrs = context;}
        {
          name = "system-state-context";
          attrs.systemStateVersion = (nullable types.str) // {
            description = "Initial NixOS state compatibility version for this host.";
          };
        }
      ];
    }).merged;
    features = featureOptions nixosFeatureNames;

    users = mkOption {
      default = {};
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
          };
          context = {
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
  nixosOptionsModule = {config, ...}: {
    _file = toString ./options.nix;
    options.local = nixosOptions featuresLib.actualFeatureOptions;

    config = lib.mkIf (config.local.context.systemStateVersion != null) {
      system.stateVersion = config.local.context.systemStateVersion;
    };
  };

  homeFeatureOptionsModule.options.local = {
    user = homeUser;
    context = (composition.namedDisjoint {
      label = "embedded-home-context-options";
      layers = [
        {name = "shared-context"; attrs = context;}
        {name = "home-manager-context"; attrs = homeContext;}
      ];
    }).merged;
    features = featuresLib.actualFeatureOptions homeFeatureNames;
  };

  nixosConfigurationModuleType = seedModuleType (nixosOptions featuresLib.seedFeatureOptions);

  homeConfigurationModuleType = seedModuleType {
    user = composition.overrideExisting {
      label = "standalone-home-user-optional-fields";
      base = homeUser;
      replacements = {
        name = nullable homeUser.name.type;
        homeDirectory = nullable homeUser.homeDirectory.type;
      };
    };
    context = composition.overrideExisting {
      label = "standalone-home-context-optional-name";
      base = (composition.namedDisjoint {
        label = "standalone-home-context-options";
        layers = [
          {name = "shared-context"; attrs = context;}
          {name = "home-manager-context"; attrs = homeContext;}
        ];
      }).merged;
      replacements.homeConfigurationName =
        nullable homeContext.homeConfigurationName.type;
    };
    features = featuresLib.seedFeatureOptions homeFeatureNames;
  };
}
