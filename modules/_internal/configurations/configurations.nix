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
  policiesLib = import ../../10-foundations/_policy/lib.nix {inherit lib fpConfig;};
  composition = import ../../../lib/composition.nix {inherit lib;};
  seedLib = import ./lib/seed.nix {inherit lib featuresLib usersLib composition;};

  nixosModules = modulesLib.publicModuleAttrs (fpConfig.flake.modules.nixos or {});
  homeModules = modulesLib.publicModuleAttrs (fpConfig.flake.modules.homeManager or {});

  nixosFeatureNames = lib.attrNames nixosModules;
  homeFeatureNames = lib.attrNames homeModules;

  helpers = fpConfig.flake.lib.helpers;

  nixosModuleList = lib.mapAttrsToList modulesLib.tagNixosModule nixosModules;
  homeModuleList = lib.mapAttrsToList modulesLib.tagHomeModule homeModules;

  optionsMaterializers = import ./materializers/options.nix {
    inherit lib nixosFeatureNames homeFeatureNames featuresLib;
  };

  policyMaterializers = import ../../10-foundations/_policy/materializer.nix {
    inherit lib policiesLib usersLib;
  };

  userMaterializers = import ./materializers/users.nix {
    inherit lib nixosModules usersLib;
  };

  embeddedHome = import ./materializers/home-manager.nix {
    inherit homeModuleList;
    inherit (optionsMaterializers) homeFeatureOptionsModule;

    inherit (featuresLib) enabledFeatures;
    inherit (usersLib) enabledUsers;
  };

  nixosOverlays = fpConfig.flake.lib.nixfilesOverlays;
  # Keep attrsOf/submodule so editor tooling can descend into concrete host and user options.
  configurationOptions = moduleType:
    lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          system = lib.mkOption {
            type = lib.types.str;
            default = "x86_64-linux";
          };
          module = lib.mkOption {
            type = moduleType;
            default = {};
          };
        };
      });
      default = {};
    };
in {
  options.configurations = {
    nixos = configurationOptions optionsMaterializers.nixosConfigurationModuleType;
    homeManager = configurationOptions optionsMaterializers.homeConfigurationModuleType;
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
              optionsMaterializers.nixosOptionsModule
              userMaterializers.userSeededNixosFeaturesModule
              policyMaterializers.nixosPolicyMaterializerModule
              policyMaterializers.nixpkgsPolicyModule
              userMaterializers.nixosUserAccountsModule
              {
                nixpkgs.overlays = nixosOverlays;
              }
              embeddedHome
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
            ++ [
              (seedLib.compactHomeSeedModule cfg.module)
            ];
        }
    )
    fpConfig.configurations.homeManager;
}
