{
  lib,
  fpConfig,
  usersLib,
}: let
  features = import ../../../lib/features.nix {inherit lib;};
  policies = import ../../../lib/policies.nix {inherit lib features;};
  policyForFeatures = policies.policyForFeatures fpConfig;
in {
  nixpkgsPolicyModule = {
    config,
    lib,
    ...
  }: let
    # One shared thunk for all package checks: build a name-indexed set
    # instead of repeatedly deduplicating and scanning an allowlist.
    allowedUnfree = lib.genAttrs config.local.nixpkgsPolicy.unfree (_: true);
  in {
    options.local.nixpkgsPolicy = lib.mkOption {
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

    config.nixpkgs.config = {
      allowUnfreePredicate = pkg:
        builtins.hasAttr (lib.getName pkg) allowedUnfree;

      permittedInsecurePackages =
        lib.unique config.local.nixpkgsPolicy.permittedInsecure;
    };
  };

  nixosPolicyMaterializerModule = {
    config,
    lib,
    ...
  }: let
    systemPolicy = policyForFeatures config.local.features;

    userPolicies =
      lib.mapAttrsToList
      (_userName: user: policyForFeatures user.features)
      (usersLib.enabledUsers config.local.users);

    policy = policies.mergePolicies ([systemPolicy] ++ userPolicies);
  in {
    config = {
      local.nixpkgsPolicy.unfree = lib.mkAfter policy.unfree;
      local.nixpkgsPolicy.permittedInsecure = lib.mkAfter policy.permittedInsecure;
    };
  };

  homePolicyMaterializerModule = {
    config,
    lib,
    ...
  }: let
    policy = policyForFeatures config.local.features;
  in {
    config = {
      local.nixpkgsPolicy.unfree = lib.mkAfter policy.unfree;
      local.nixpkgsPolicy.permittedInsecure = lib.mkAfter policy.permittedInsecure;
    };
  };
}
