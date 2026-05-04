{lib, ...}: let
  allowUnfreeModule = {config, ...}: {
    options.policy.pkgs.allowUnfreeNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Package names allowed by nixpkgs.config.allowUnfreePredicate.";
    };

    config.nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) config.policy.pkgs.allowUnfreeNames;
  };
in {
  config.flake.modules.nixos.policyAllowUnfreeNames =
    allowUnfreeModule;

  config.flake.modules.homeManager.policyAllowUnfreeNames =
    allowUnfreeModule;
}
