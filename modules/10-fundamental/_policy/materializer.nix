{
  lib,
  policiesLib,
  usersLib,
}: rec {
  nixpkgsPolicyModule = {
    config,
    lib,
    ...
  }: {
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
        builtins.elem
        (lib.getName pkg)
        (lib.unique config.local.nixpkgsPolicy.unfree);

      permittedInsecurePackages =
        lib.unique config.local.nixpkgsPolicy.permittedInsecure;
    };
  };

  nixosPolicyMaterializerModule = {
    config,
    lib,
    ...
  }: let
    systemPolicy = policiesLib.policyForFeatures config.local.features;

    userPolicies =
      lib.mapAttrsToList
      (_userName: user: policiesLib.policyForFeatures user.features)
      (usersLib.enabledUsers config.local.users);

    policy = policiesLib.mergePolicies ([systemPolicy] ++ userPolicies);
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
    policy = policiesLib.policyForFeatures config.local.features;
  in {
    config = {
      local.nixpkgsPolicy.unfree = lib.mkAfter policy.unfree;
      local.nixpkgsPolicy.permittedInsecure = lib.mkAfter policy.permittedInsecure;
    };
  };
}
