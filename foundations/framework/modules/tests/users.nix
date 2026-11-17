{lib}: let
  featuresLib = import ../lib/features.nix {inherit lib;};
  usersLib = import ../lib/users.nix {inherit lib featuresLib;};
  projection = import ../materializers/users.nix {
    inherit lib usersLib;
    nixosModules = {steam = {};};
  };
  projectionConfig = disabled:
    (lib.evalModules {
      modules = [
        ({lib, ...}: {
          options.local.users = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
          options.local.features.steam.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          options.assertions = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [];
          };
          config = {
            local.users.alice = {
              enable = true;
              features.steam.enable = true;
            };
          } // lib.optionalAttrs disabled {
            local.features.steam.enable = false;
          };
        })
        projection.userSeededNixosFeaturesModule
      ];
    }).config;
in {
  testEnabledUsersExcludesExplicitFalse = {
    expr = usersLib.enabledUsers {
      alice = {enable = false;};
      bob = {enable = true;};
    };
    expected = {
      bob = {enable = true;};
    };
  };

  testEnabledUsersIncludesImplicitEnabled = {
    expr = usersLib.enabledUsers {
      alice = {};
      carol = {enable = true;};
    };
    expected = {
      alice = {};
      carol = {enable = true;};
    };
  };

  testCompactNixosUsersCompactsFeatures = {
    expr = usersLib.compactNixosUsers {
      alice = {
        enable = true;
        isAdmin = false;
        email = "";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {
          hyprland = {enable = true;};
          zsh = {enable = null;};
          x = {};
        };
      };
    };
    expected = {
      alice = {
        enable = true;
        isAdmin = false;
        email = "";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {
          hyprland = {enable = true;};
        };
      };
    };
  };

  testCompactNixosUsersPreservesUserFields = {
    expr = usersLib.compactNixosUsers {
      alice = {
        enable = true;
        isAdmin = false;
        email = "alice@x";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {};
      };
    };
    expected = {
      alice = {
        enable = true;
        isAdmin = false;
        email = "alice@x";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {};
      };
    };
  };
  testUserFeatureAutomaticallyProjectsToNixos = {
    expr = (projectionConfig false).local.features.steam.enable;
    expected = true;
  };

  testUserFeatureSystemDisableIsRejectedByAssertion = {
    expr = (builtins.head (projectionConfig true).assertions).assertion;
    expected = false;
  };

  testProjectedUserFeatureAssertionPasses = {
    expr = (builtins.head (projectionConfig false).assertions).assertion;
    expected = true;
  };
}
