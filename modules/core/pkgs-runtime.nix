{
  inputs,
  lib,
  ...
}: let
  pkgsOptions = {
    options.local.pkgs.useUnstable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose inputs.nixpkgs-unstable as pkgs.unstable.";
    };

    options.policy.pkgs.allowUnfreeNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Package names allowed by nixpkgs.config.allowUnfreePredicate.";
    };

    options.policy.pkgs.allowUnfreePredicates = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [];
      description = "Additional predicates used by nixpkgs.config.allowUnfreePredicate.";
    };

    options.policy.pkgs.permittedInsecurePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Insecure package versions explicitly permitted for this configuration.";
    };
  };

  pkgsRuntime = {config, ...}: let
    localPkgs = config.local.pkgs;
    policyPkgs = config.policy.pkgs;

    hasUnfreePolicy =
      policyPkgs.allowUnfreeNames
      != []
      || policyPkgs.allowUnfreePredicates != [];
  in {
    imports = [
      pkgsOptions
    ];

    config = lib.mkMerge [
      (lib.mkIf localPkgs.useUnstable {
        nixpkgs.overlays = [
          (final: prev: {
            unstable = import inputs.nixpkgs-unstable {
              system = prev.stdenv.hostPlatform.system;
              config = prev.config;
            };
          })
        ];
      })

      (lib.mkIf hasUnfreePolicy {
        nixpkgs.config.allowUnfreePredicate = pkg:
          builtins.elem (lib.getName pkg) policyPkgs.allowUnfreeNames
          || builtins.any (predicate: predicate pkg) policyPkgs.allowUnfreePredicates;
      })

      (lib.mkIf (policyPkgs.permittedInsecurePackages != []) {
        nixpkgs.config.permittedInsecurePackages =
          policyPkgs.permittedInsecurePackages;
      })
    ];
  };
in {
  config.flake.modules.nixos.pkgsRuntime =
    pkgsRuntime;

  config.flake.modules.homeManager.pkgsOptions =
    pkgsOptions;

  config.flake.modules.homeManager.pkgsRuntime =
    pkgsRuntime;
}
