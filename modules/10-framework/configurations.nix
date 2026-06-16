{
  config,
  lib,
  inputs,
  ...
}: let
  fpConfig = config;

  publicModuleAttrs = attrs:
    lib.filterAttrs (name: _value: !(lib.hasPrefix "_" name)) attrs;

  nixosModules = publicModuleAttrs (fpConfig.flake.modules.nixos or {});
  homeModules = publicModuleAttrs (fpConfig.flake.modules.homeManager or {});

  nixosFeatureNames = lib.attrNames nixosModules;
  homeFeatureNames = lib.attrNames homeModules;

  helpers = fpConfig.flake.lib.helpers;

  actualFeatureOptions = featureNames:
    lib.genAttrs featureNames (featureName: {
      enable = lib.mkEnableOption featureName;
    });

  # Seed options are for the flake-parts-side host declaration surface.
  # Use null instead of false so "not specified" does not propagate as an explicit disabled feature.
  seedFeatureOptions = featureNames:
    lib.genAttrs featureNames (featureName: {
      enable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          Seed activation for ${featureName}.

          null means "not specified in this seed module".
          true/false are emitted into the real module passed to the target module system.
        '';
      };
    });

  enabledFeatures = features:
    lib.mapAttrs
    (_name: _feature: {
      enable = true;
    })
    (lib.filterAttrs
      (_name: feature: feature.enable or false)
      features);

  enabledUsers = users:
    lib.filterAttrs
    (_name: user: user.enable or true)
    users;

  # Remove null seed values before handing the module to NixOS/Home Manager.
  # This preserves "unspecified" semantics and avoids seed defaults overriding real module defaults.
  compactFeatureSet = features:
    lib.mapAttrs
    (_name: feature: {
      enable = feature.enable;
    })
    (lib.filterAttrs
      (_name: feature: (feature.enable or null) != null)
      features);

  compactContext = context:
    lib.filterAttrs
    (_name: value: value != null)
    context;

  compactNixosUsers = users:
    lib.mapAttrs
    (name: user: {
      enable = user.enable;
      isAdmin = user.isAdmin;
      email = user.email;
      homeDirectory = user.homeDirectory;
      homeStateVersion = user.homeStateVersion;
      features = compactFeatureSet user.features;
    })
    users;

  # Convert the typed flake-parts host seed back into a plain NixOS module.
  # This keeps editor-visible seed options while preventing null/default seed state from leaking downstream.
  compactNixosSeedModule = module: let
    local = module.local or {};
    rest = removeAttrs module ["_module" "local"];
  in
    rest
    // {
      local =
        {
          features = compactFeatureSet (local.features or {});
          users = compactNixosUsers (local.users or {});
        }
        // lib.optionalAttrs (local ? context) {
          context = compactContext local.context;
        };
    };

  # Convert the typed flake-parts Home Manager seed back into a plain HM module.
  # Keep only explicitly specified seed values before passing it to homeManagerConfiguration.
  compactHomeSeedModule = module: let
    local = module.local or {};
    rest = removeAttrs module ["_module" "local"];
  in
    rest
    // lib.optionalAttrs (module ? local) {
      local =
        lib.optionalAttrs (local ? features) {
          features = compactFeatureSet local.features;
        }
        // lib.optionalAttrs (local ? context) {
          context = compactContext local.context;
        }
        // lib.optionalAttrs (local ? user) {
          user = local.user;
        };
    };

  policyForFeatures = features: let
    enabledNames =
      lib.attrNames
      (lib.filterAttrs
        (_name: feature: feature.enable or false)
        features);

    policies =
      map
      (name: fpConfig.flake.local.featurePolicies.${name} or {})
      enabledNames;
  in {
    unfree =
      lib.concatMap
      (policy: policy.unfree or [])
      policies;

    permittedInsecure =
      lib.concatMap
      (policy: policy.permittedInsecure or [])
      policies;
  };

  mergePolicies = policies: {
    unfree =
      lib.concatMap
      (policy: policy.unfree or [])
      policies;

    permittedInsecure =
      lib.concatMap
      (policy: policy.permittedInsecure or [])
      policies;
  };

  nixosPolicyMaterializerModule = {
    config,
    lib,
    ...
  }: let
    systemPolicy =
      policyForFeatures config.local.features;

    userPolicies =
      lib.mapAttrsToList
      (_userName: user: policyForFeatures user.features)
      (enabledUsers config.local.users);

    policy =
      mergePolicies ([systemPolicy] ++ userPolicies);
  in {
    config = {
      local.nixpkgsPolicy.unfree =
        lib.mkAfter policy.unfree;

      local.nixpkgsPolicy.permittedInsecure =
        lib.mkAfter policy.permittedInsecure;
    };
  };

  homePolicyMaterializerModule = {
    config,
    lib,
    ...
  }: let
    policy =
      policyForFeatures config.local.features;
  in {
    config = {
      local.nixpkgsPolicy.unfree =
        lib.mkAfter policy.unfree;

      local.nixpkgsPolicy.permittedInsecure =
        lib.mkAfter policy.permittedInsecure;
    };
  };

  userSeededNixosFeaturesModule = {
    config,
    lib,
    ...
  }: let
    users = enabledUsers config.local.users;

    enabledUserFeatureNames = lib.unique (
      lib.concatMap
      (user:
        lib.attrNames (
          lib.filterAttrs
          (_name: feature: feature.enable or false)
          user.features
        ))
      (lib.attrValues users)
    );

    names =
      lib.filter
      (name: builtins.hasAttr name nixosModules)
      enabledUserFeatureNames;
  in {
    config.local.features = lib.genAttrs names (_name: {
      enable = lib.mkDefault true;
    });
  };

  nixosUserAccountsModule = {
    config,
    lib,
    ...
  }: let
    users = enabledUsers config.local.users;
  in {
    config = {
      users.groups =
        lib.mapAttrs
        (_name: _user: {})
        users;

      users.users =
        lib.mapAttrs
        (name: user: {
          isNormalUser = lib.mkDefault true;
          group = name;
          home = user.homeDirectory;

          extraGroups =
            lib.mkAfter
            (lib.optional user.isAdmin "wheel");
        })
        users;
    };
  };

  unstableOverlay = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = prev.stdenv.hostPlatform.system;
      config = prev.config;
    };
  };

  nixosOverlays = [
    inputs.llm-agents.overlays.default
    unstableOverlay
  ];

  tagNixosModule = name: module: {
    _file = "flake.modules.nixos.${name}";
    imports = [module];
  };

  tagHomeModule = name: module: {
    _file = "flake.modules.homeManager.${name}";
    imports = [module];
  };

  nixosModuleList = lib.mapAttrsToList tagNixosModule nixosModules;
  homeModuleList = lib.mapAttrsToList tagHomeModule homeModules;

  nixosFeatureOptionsModule = {lib, ...}: {
    options.local = {
      features = actualFeatureOptions nixosFeatureNames;

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

                features = actualFeatureOptions homeFeatureNames;
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

      features = actualFeatureOptions homeFeatureNames;
    };
  };

  nixpkgsPolicyModule = {
    config,
    lib,
    ...
  }: {
    options.local.nixpkgsPolicy = lib.mkOption {
      type = lib.types.submodule {
        options = {
          unfree = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };

          permittedInsecure = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
        };
      };
      default = {};
    };

    config.nixpkgs.config = {
      allowUnfreePredicate = pkg:
        builtins.elem
        (lib.getName pkg)
        (lib.unique config.local.nixpkgsPolicy.unfree);

      permittedInsecurePackages =
        lib.unique config.local.nixpkgsPolicy.permittedInsecure;
    };
  };

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
        (userName: user: {
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
        })
        (enabledUsers config.local.users);
    };
  };

  # Do not use types.deferredModule here. It is valid for delayed module evaluation,
  # but opaque to flake-parts debug.options, so nixd cannot see module.local.* seed options.
  nixosConfigurationModuleType = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.anything;

    options.local = {
      features = seedFeatureOptions nixosFeatureNames;

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

                features = seedFeatureOptions homeFeatureNames;
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

      features = seedFeatureOptions homeFeatureNames;
    };
  };
in {
  options.configurations.nixos = lib.mkOption {
    # nixd/Zed does not reliably descend through lazyAttrsOf when resolving flake-parts debug.options.
    # Keep this as attrsOf so concrete paths like configurations.nixos.neko5.module expose nested seed options.
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          system = lib.mkOption {
            type = lib.types.str;
            default = "x86_64-linux";
          };

          module = lib.mkOption {
            type = nixosConfigurationModuleType;
            default = {};
          };
        };
      }
    );
    default = {};
  };

  options.configurations.homeManager = lib.mkOption {
    # Same editor constraint as configurations.nixos: lazyAttrsOf hides nested seed declarations from nixd.
    # attrsOf keeps host/user paths concrete enough for flake-parts debug.options completion.
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          system = lib.mkOption {
            type = lib.types.str;
            default = "x86_64-linux";
          };

          module = lib.mkOption {
            type = homeConfigurationModuleType;
            default = {};
          };
        };
      }
    );
    default = {};
  };

  config.flake.nixosConfigurations =
    lib.mapAttrs
    (name: cfg:
      inputs.nixpkgs.lib.nixosSystem {
        system = cfg.system;

        specialArgs = {
          inherit helpers;
        };

        modules =
          [
            inputs.home-manager.nixosModules.home-manager
            nixosFeatureOptionsModule
            userSeededNixosFeaturesModule
            nixosPolicyMaterializerModule
            nixpkgsPolicyModule
            nixosUserAccountsModule
            {
              nixpkgs.overlays = nixosOverlays;
            }
            hmFactoryModule
            {
              networking.hostName = lib.mkDefault name;
            }
            {
              local.context = {
                hostName = lib.mkDefault name;
                nixosConfigurationName = lib.mkDefault name;
              };
            }
          ]
          ++ nixosModuleList
          ++ [
            # cfg.module is a typed flake-parts seed, not the final NixOS module surface.
            # Compact it first so only explicitly specified seed values enter the real module system.
            (compactNixosSeedModule cfg.module)
          ];
      })
    fpConfig.configurations.nixos;

  config.flake.homeConfigurations =
    lib.mapAttrs
    (_name: cfg: let
      basePkgs = inputs.nixpkgs.legacyPackages.${cfg.system};
      overlayedPkgs = basePkgs.appendOverlays nixosOverlays;
    in
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = overlayedPkgs;

        extraSpecialArgs = {
          inherit helpers;
        };

        modules =
          [
            homeFeatureOptionsModule
            homePolicyMaterializerModule
            nixpkgsPolicyModule
            {
              programs.home-manager.enable = lib.mkDefault true;
              xdg.enable = lib.mkDefault true;
              home.preferXdgDirectories = lib.mkDefault true;
            }
          ]
          ++ homeModuleList
          ++ [
            # cfg.module is a typed flake-parts seed, not the final Home Manager module surface.
            # Compact it first so only explicitly specified seed values enter the real module system.
            (compactHomeSeedModule cfg.module)
          ];
      })
    fpConfig.configurations.homeManager;
}
