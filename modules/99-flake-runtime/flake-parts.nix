{
  config,
  lib,
  inputs,
  ...
}: {
  imports = [inputs.flake-parts.flakeModules.modules];

  options.flake.effects = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule {
      options = {
        requires = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            Other feature names this feature depends on.
            The materializer (`feature.system` / `feature.users`)
            resolves the closure before projection.
            Feature names are kebab-case.
          '';
        };

        user = lib.mkOption {
          type = lib.types.raw;
          default = null;
          description = ''
            User-side projection contract.
            Either a set (treated as the projection result) or a
            function `args: { config = {...}; collect = {...}; }`.
            `args` is `{ user, lib, ... }` where `user` is a record
            (`{ name, fullName, email, isAdmin, shell, homeStateVersion, homeDirectory }`).
            `config` is merged into the user's NixOS module.
            `collect` is merged into `local.effects.*`.
            Default `null` means "no user-side projection."
            Direct projectability checks distinguish `null` from
            explicit empty projections.
          '';
        };

        system = lib.mkOption {
          type = lib.types.raw;
          default = null;
          description = ''
            System-side projection contract.
            Either a set (treated as the projection result) or a
            function `args: { config = {...}; collect = {...}; }`.
            `args` is `{ lib, ... }`.
            `config` is merged into the host NixOS module.
            `collect` is merged into `local.effects.*`.
            Default `null` means "no system-side projection."
            Direct projectability checks distinguish `null` from
            explicit empty projections.
          '';
        };
      };
    });
    default = {};
    description = ''
      Per-feature projection contracts. `requires` is the dependency edge,
      `user` and `system` are projection rules that contribute to
      `config` (NixOS module attributes) and `collect`
      (cross-cutting policy, projected by the collector aspect).
    '';
  };

  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = {};
    description = ''
      Materializer / factory surface exposed to host modules via
      `_module.args` (e.g. `feature`, `userFactory`).
    '';
  };

  config = {
    _module.args = {
      nixos = config.flake.modules.nixos;
      homeManager = config.flake.modules.homeManager;
      feature = config.flake.lib.feature;
      userFactory = config.flake.lib.userFactory;
    };

    flake.modules = {
      homeManager = {};
      nixos = {};
    };
  };
}
