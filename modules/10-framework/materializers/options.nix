{
  lib,
  nixosFeatureNames,
  homeFeatureNames,
  featuresLib,
}: rec {
  nixosFeatureOptionsModule = {lib, ...}: {
    options.local = {
      features = featuresLib.actualFeatureOptions nixosFeatureNames;

      users = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (
          lib.types.submodule (
            {name, ...}: {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };

                isAdmin = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };

                email = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                };

                homeDirectory = lib.mkOption {
                  type = lib.types.str;
                  default = "/home/${name}";
                };

                homeStateVersion = lib.mkOption {
                  type = lib.types.str;
                  default = "26.05";
                };

                features = featuresLib.actualFeatureOptions homeFeatureNames;
              };
            }
          )
        );
      };

      context = {
        flakePath = lib.mkOption {
          type = lib.types.str;
          default = "/home/tenzyu/.nixfiles"; # TODO: configuration.nix に promote
        };

        hostName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        nixosConfigurationName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
    };
  };

  homeFeatureOptionsModule = {lib, ...}: {
    options.local = {
      user = {
        name = lib.mkOption {
          type = lib.types.str;
        };

        email = lib.mkOption {
          type = lib.types.str;
          default = "";
        };

        homeDirectory = lib.mkOption {
          type = lib.types.str;
        };

        stateVersion = lib.mkOption {
          type = lib.types.str;
          default = "26.05";
        };
      };

      context = {
        flakePath = lib.mkOption {
          type = lib.types.str;
        };

        hostName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        nixosConfigurationName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        homeConfigurationName = lib.mkOption {
          type = lib.types.str;
        };

        embeddedInNixOS = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };

      features = featuresLib.actualFeatureOptions homeFeatureNames;
    };
  };

  # Do not use types.deferredModule here. It is valid for delayed module evaluation,
  # but opaque to flake-parts debug.options, so nixd cannot see module.local.* seed options.
  nixosConfigurationModuleType = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.anything;

    options.local = {
      features = featuresLib.seedFeatureOptions nixosFeatureNames;

      users = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (
          lib.types.submodule (
            {name, ...}: {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };

                isAdmin = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };

                email = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                };

                homeDirectory = lib.mkOption {
                  type = lib.types.str;
                  default = "/home/${name}";
                };

                homeStateVersion = lib.mkOption {
                  type = lib.types.str;
                  default = "26.05";
                };

                features = featuresLib.seedFeatureOptions homeFeatureNames;
              };
            }
          )
        );
      };

      context = {
        flakePath = lib.mkOption {
          type = lib.types.str;
          default = "/home/tenzyu/.nixfiles"; # TODO: configuration.nix に promote
        };

        hostName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        nixosConfigurationName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
    };
  };

  # Same reason as the NixOS seed module type above: keep the declaration editor-visible,
  # then compact it into a plain Home Manager module before evaluation.
  homeConfigurationModuleType = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.anything;

    options.local = {
      user = {
        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        email = lib.mkOption {
          type = lib.types.str;
          default = "";
        };

        homeDirectory = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        stateVersion = lib.mkOption {
          type = lib.types.str;
          default = "26.05";
        };
      };

      context = {
        flakePath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        hostName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        nixosConfigurationName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        homeConfigurationName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        embeddedInNixOS = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };

      features = featuresLib.seedFeatureOptions homeFeatureNames;
    };
  };
}
