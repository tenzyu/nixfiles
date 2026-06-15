{
  config,
  inputs,
  lib,
  withSystem,
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
    withSystem system ({inputs', ...}: let
      basePkgs = inputs'.nixpkgs.legacyPackages;
      overlayedPkgs = basePkgs.appendOverlays [
        inputs.llm-agents.overlays.default

        (final: prev: {
          unstable = import inputs.nixpkgs-unstable {
            system = prev.stdenv.hostPlatform.system;
            config = prev.config;
          };
        })
      ];
    in
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = overlayedPkgs;
        modules = [
          config.flake.modules.homeManager.context
          {
            local.hm.context = "standalone";
          }
          ({lib, ...}: {
            programs.home-manager.enable = lib.mkDefault true;
            xdg.enable = lib.mkDefault true;
            home.preferXdgDirectories = lib.mkDefault true;
            home.username = lib.mkDefault "tenzyu";
            home.homeDirectory = lib.mkDefault "/home/tenzyu";
            home.stateVersion = lib.mkDefault "26.05";
          })
          module
        ];
      }))
  config.configurations.homeManager;
}
