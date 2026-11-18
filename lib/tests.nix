{lib}: let
  features = import ./features.nix {inherit lib;};
  users = import ./users.nix {inherit lib features;};
  policies = import ./policies.nix {inherit lib features;};
  cfg = {
    local.users = {
      alice = {enable = true; features = {steam.enable = true; git.enable = false;};};
      bob = {enable = false; features.steam.enable = true;};
      carol = {features.steam.enable = true;};
      dave = {features = {};};
    };
  };
  flakeConfig.flake.local.featurePolicies = {
    alpha = {unfree = ["steam"];};
    gamma = {unfree = ["steam" "minecraft"]; permittedInsecure = ["legacy"];};
  };
in {
  testMissingAndExplicitlyDisabledFeatures = {
    expr = {
      missing = features.featureEnabled "unknown" {alpha.enable = true;};
      disabled = features.featureEnabled "beta" {beta.enable = false;};
      enabled = features.featureEnabled "alpha" {alpha.enable = true;};
      names = features.enabledFeatureNames {gamma.enable = true; alpha.enable = true; beta.enable = false; delta = {};};
    };
    expected = {missing = false; disabled = false; enabled = true; names = ["alpha" "gamma"];};
  };

  testUserSelectionSkipsDisabledUsers = {
    expr = {
      names = users.userNamesWithFeature "steam" cfg;
      mapped = users.mapUsersWithFeature "steam" cfg (name: _: "selected-${name}");
      none = users.userNamesWithFeature "missing" cfg;
    };
    expected = {
      names = ["alice" "carol"];
      mapped = {alice = "selected-alice"; carol = "selected-carol";};
      none = [];
    };
  };

  testPolicyAggregationPreservesOrderingAndExistingDuplicates = {
    expr = policies.policyForFeatures flakeConfig {
      gamma.enable = true;
      beta.enable = false;
      alpha.enable = true;
      delta = {};
    };
    expected = {unfree = ["steam" "steam" "minecraft"]; permittedInsecure = ["legacy"];};
  };

  testEmptyPolicyAndMissingPolicyStayEmpty = {
    expr = {
      empty = policies.mergePolicies [];
      notRegistered = policies.policyForFeatures flakeConfig {unused.enable = true;};
    };
    expected = {
      empty = {unfree = []; permittedInsecure = [];};
      notRegistered = {unfree = []; permittedInsecure = [];};
    };
  };
}
