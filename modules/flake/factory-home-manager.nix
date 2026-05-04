{
  config,
  inputs,
  lib,
  withSystem,
  ...
}: let
  inherit (config.me) stateVersion username;
in {
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
    withSystem system ({inputs', ...}:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs'.nixpkgs.legacyPackages;
        modules = [
          config.flake.modules.homeManager.pkgsRuntime
          ({lib, ...}: {
            programs.home-manager.enable = lib.mkDefault true;
            xdg.enable = lib.mkDefault true;
            home.preferXdgDirectories = lib.mkDefault true;
            home.username = lib.mkDefault username;
            home.homeDirectory = lib.mkDefault "/home/${username}";
            home.stateVersion = lib.mkDefault stateVersion;
          })
          module
        ];
      }))
  config.configurations.homeManager;
}
