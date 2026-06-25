{
  inputs,
  lib,
  ...
}: {
  imports = [inputs.flake-parts.flakeModules.modules];

  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = {};
    description = ''
      Framework helper surface exposed to host modules via `_module.args`
      (e.g. `helpers`).
    '';
  };

  options.flake.local.featurePolicies = lib.mkOption {
    default = {};
    type = lib.types.attrsOf (lib.types.submodule {
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
    });
    description = ''
      Per-feature package admissibility policy declarations. Each feature
      module may declare its required unfree and permittedInsecure package
      names here; the framework materializer collects the active feature
      set's policy into `local.nixpkgsPolicy`.
    '';
  };

  config = {
    # NOTE: Expose flake-parts option declarations for nixd via .#debug.options.
    #       Required for completion inside configurations.nixos.<host>.module, which belongs to the flake-parts option universe.
    debug = true;

    flake.modules = {
      homeManager = {};
      nixos = {};
    };
  };
}
