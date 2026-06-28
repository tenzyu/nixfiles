{
  inputs,
  lib,
  ...
}: let
  payloadOption = lib.mkOption {
    type = lib.types.nullOr lib.types.raw;
    default = null;
    description = ''
      Native feature config-fragment payload. The payload is called with
      feature/boundary context and must return a config fragment, not a module.
    '';
  };

  projectionType = lib.types.submodule {
    options.payload = payloadOption;
  };

  joinType = projectionType;

  contributionType = lib.types.submodule {
    options = {
      when.sameBoundary.features = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };

      payload = payloadOption;
    };
  };
in {
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

  options.flake.features = lib.mkOption {
    default = {};
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        options = lib.mkOption {
          type = lib.types.raw;
          default = {};
          description = ''
            Feature-specific setting option declarations. These are expanded
            into local.features.<feature> and user/container feature subtrees.
          '';
        };

        projections = {
          nixos = lib.mkOption {
            type = projectionType;
            default = {};
          };

          homeManager = lib.mkOption {
            type = projectionType;
            default = {};
          };
        };

        joins = {
          userToNixos = lib.mkOption {
            type = joinType;
            default = {};
          };

          nixosContainerToHost = lib.mkOption {
            type = joinType;
            default = {};
          };
        };

        contributions = {
          nixos = lib.mkOption {
            type = lib.types.attrsOf contributionType;
            default = {};
          };

          homeManager = lib.mkOption {
            type = lib.types.attrsOf contributionType;
            default = {};
          };
        };

        policy = lib.mkOption {
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
      };
    });
    description = ''
      Native boundary-aware feature projection declarations. Native payloads
      are config fragments; arbitrary modules remain available through
      flake.modules.* as the escape hatch.
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

    flake.features = {};
  };
}
