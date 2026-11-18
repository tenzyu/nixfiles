{
  lib,
  fpConfig,
}: let
  features = import ../../../lib/features.nix {inherit lib;};
  policies = import ../../../lib/policies.nix {inherit lib features;};
in {
  policyForFeatures = policies.policyForFeatures fpConfig;
  inherit (policies) mergePolicies;
}
