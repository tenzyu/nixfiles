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

  config.flake.nixosConfigurations = lib.mapAttrs (name: {
    system,
    module,
  }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        config.flake.modules.nixos.pkgsRuntime
        inputs.home-manager.nixosModules.home-manager
        {
          networking.hostName = lib.mkDefault name;

          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.sharedModules = [
            config.flake.modules.homeManager.pkgsOptions
          ];
        }
        module
      ];
    })
  config.configurations.nixos;
}
