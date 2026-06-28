{
  config,
  lib,
  inputs,
  ...
}: let
  fpConfig = config;

  modulesLib = import ./lib/modules.nix {inherit lib;};
  featuresLib = import ./lib/features.nix {inherit lib;};
  usersLib = import ./lib/users.nix {inherit lib featuresLib;};
  policiesLib = import ./lib/policies.nix {inherit lib fpConfig;};
  seedLib = import ./lib/seed.nix {inherit lib featuresLib usersLib;};

  nixosModules = modulesLib.publicModuleAttrs (fpConfig.flake.modules.nixos or {});
  homeModules = modulesLib.publicModuleAttrs (fpConfig.flake.modules.homeManager or {});
  nativeFeatures = featuresLib.publicFeatureAttrs (fpConfig.flake.features or {});

  nativeFeatureNames = lib.attrNames nativeFeatures;
  nixosFeatureNames = lib.unique ((lib.attrNames nixosModules) ++ nativeFeatureNames);
  homeFeatureNames = lib.unique ((lib.attrNames homeModules) ++ nativeFeatureNames);

  helpers = fpConfig.flake.lib.helpers;

  nixosModuleList = lib.mapAttrsToList modulesLib.tagNixosModule nixosModules;
  homeModuleList = lib.mapAttrsToList modulesLib.tagHomeModule homeModules;

  optionsMaterializers = import ./materializers/options.nix {
    inherit lib nixosFeatureNames homeFeatureNames featuresLib nativeFeatures;
  };

  nativeMaterializers = import ./materializers/native-projections.nix {
    inherit lib featuresLib usersLib nativeFeatures;
  };

  policyMaterializers = import ./materializers/policy.nix {
    inherit lib policiesLib usersLib;
  };

  userMaterializers = import ./materializers/users.nix {
    inherit lib nixosModules usersLib;
  };

  hmMaterializers = import ./materializers/home-manager.nix {
    inherit lib helpers;
    homeModuleList = homeModuleList ++ nativeMaterializers.homeProjectionModules ++ nativeMaterializers.homeContributionModules;
    inherit (optionsMaterializers) homeFeatureOptionsModule;
    inherit (policyMaterializers) nixpkgsPolicyModule;
    inherit (featuresLib) enabledFeatures;
    inherit (usersLib) enabledUsers;
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
            type = optionsMaterializers.nixosConfigurationModuleType;
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
            type = optionsMaterializers.homeConfigurationModuleType;
            default = {};
          };
        };
      }
    );
    default = {};
  };

  config.flake.nixosConfigurations =
    lib.mapAttrs
    (
      name: cfg:
        inputs.nixpkgs.lib.nixosSystem {
          system = cfg.system;

          specialArgs = {
            inherit helpers;
          };

          modules =
            [
              inputs.home-manager.nixosModules.home-manager
              optionsMaterializers.nixosFeatureOptionsModule
              userMaterializers.userSeededNixosFeaturesModule
              policyMaterializers.nixosPolicyMaterializerModule
              policyMaterializers.nixpkgsPolicyModule
              userMaterializers.nixosUserAccountsModule
              {
                nixpkgs.overlays = nixosOverlays;
              }
              hmMaterializers.hmFactoryModule
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
            ++ nativeMaterializers.nixosProjectionModules
            ++ nativeMaterializers.seededUserToNixosJoinModules {
              hostName = name;
              seedModule = cfg.module;
            }
            ++ [
              # cfg.module is a typed flake-parts seed, not the final NixOS module surface.
              # Compact it first so only explicitly specified seed values enter the real module system.
              (seedLib.compactNixosSeedModule cfg.module)
            ];
        }
    )
    fpConfig.configurations.nixos;

  config.flake.homeConfigurations =
    lib.mapAttrs
    (
      _name: cfg: let
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
              optionsMaterializers.homeFeatureOptionsModule
              policyMaterializers.homePolicyMaterializerModule
              policyMaterializers.nixpkgsPolicyModule
              {
                programs.home-manager.enable = lib.mkDefault true;
                xdg.enable = lib.mkDefault true;
                home.preferXdgDirectories = lib.mkDefault true;
              }
            ]
            ++ homeModuleList
            ++ nativeMaterializers.homeProjectionModules
            ++ nativeMaterializers.homeContributionModules
            ++ [
              # cfg.module is a typed flake-parts Home Manager seed, not the final Home Manager module surface.
              # Compact it first so only explicitly specified seed values enter the real module system.
              (seedLib.compactHomeSeedModule cfg.module)
            ];
        }
    )
    fpConfig.configurations.homeManager;
}
