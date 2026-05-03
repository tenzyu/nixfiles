{
  config,
  inputs,
  lib,
  ...
}: {
  options.configurations.nixos = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule {
      options = {
        system = lib.mkOption {
          type = lib.types.str;
          default = "x86_64-linux";
        };

        module = lib.mkOption {
          type = lib.types.deferredModule;
        };
      };
    });
    default = {};
  };

  config.flake.nixosConfigurations = lib.mapAttrs (_: {
    system,
    module,
  }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
        }
        module
      ];
    })
  config.configurations.nixos;
}
