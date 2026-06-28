{
  lib,
  nixosFeatureNames,
  homeFeatureNames,
  featuresLib,
  nativeFeatures ? {},
}: let
  bindMountOptions = {lib, ...}: {
    options = {
      hostPath = lib.mkOption {
        type = lib.types.str;
      };

      isReadOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };

  containerOptions = {
    name,
    lib,
    ...
  }: {
    options = {
      backend = lib.mkOption {
        type = lib.types.enum ["nixos-container"];
        default = "nixos-container";
      };

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      privateNetwork = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      enableTun = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      hostAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      localAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      nat = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        externalInterface = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };

      bindMounts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule bindMountOptions);
        default = {};
      };

      features = featuresLib.actualFeatureOptionsWithSchemas nixosFeatureNames nativeFeatures;
    };
  };

  seedContainerOptions = {
    name,
    lib,
    ...
  }: {
    options = {
      backend = lib.mkOption {
        type = lib.types.enum ["nixos-container"];
        default = "nixos-container";
      };

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      privateNetwork = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      enableTun = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      hostAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      localAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      nat = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        externalInterface = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };

      bindMounts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule bindMountOptions);
        default = {};
      };

      features = featuresLib.seedFeatureOptionsWithSchemas nixosFeatureNames nativeFeatures;
    };
  };
in rec {
  nixosFeatureOptionsModule = {lib, ...}: {
    options.local = {
      features = featuresLib.actualFeatureOptionsWithSchemas nixosFeatureNames nativeFeatures;

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

                features = featuresLib.actualFeatureOptionsWithSchemas homeFeatureNames nativeFeatures;
              };
            }
          )
        );
      };

      containers = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (lib.types.submodule containerOptions);
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

        boundaryKind = lib.mkOption {
          type = lib.types.str;
          default = "nixos";
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
          type = lib.types.str;
        };

        embeddedInNixOS = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        boundaryKind = lib.mkOption {
          type = lib.types.str;
          default = "homeManager";
        };
      };

      features = featuresLib.actualFeatureOptionsWithSchemas homeFeatureNames nativeFeatures;
    };
  };

  # Do not use types.deferredModule here. It is valid for delayed module evaluation,
  # but opaque to flake-parts debug.options, so nixd cannot see module.local.* seed options.
  nixosConfigurationModuleType = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.anything;

    options.local = {
      features = featuresLib.seedFeatureOptionsWithSchemas nixosFeatureNames nativeFeatures;

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

                features = featuresLib.seedFeatureOptionsWithSchemas homeFeatureNames nativeFeatures;
              };
            }
          )
        );
      };

      containers = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (lib.types.submodule seedContainerOptions);
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

        boundaryKind = lib.mkOption {
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

        boundaryKind = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };

      features = featuresLib.seedFeatureOptionsWithSchemas homeFeatureNames nativeFeatures;
    };
  };
}
