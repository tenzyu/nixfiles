{
  config,
  inputs,
  lib,
  ...
}: {
  options.configurations.homeManager = lib.mkOption {
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

  config.flake.homeConfigurations = lib.mapAttrs (_: {
    system,
    module,
  }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      modules = [
        config.flake.modules.homeManager.pkgsRuntime
        module
      ];
    })
  config.configurations.homeManager;
}
