{lib}: let
  fpConfig = {
    flake.local.featurePolicies = {
      alpha = {
        unfree = ["alpha-unfree"];
        permittedInsecure = ["alpha-insecure"];
      };
      beta = {
        unfree = ["beta-unfree"];
        permittedInsecure = ["beta-insecure"];
      };
    };
  };
  policiesLib = import ../lib/policies.nix {inherit lib fpConfig;};
in {
  testPolicyForFeaturesCollectsOnlyEnabled = {
    expr = policiesLib.policyForFeatures {
      alpha = {enable = true;};
      beta = {enable = false;};
      gamma = {};
    };
    expected = {
      unfree = ["alpha-unfree"];
      permittedInsecure = ["alpha-insecure"];
    };
  };

  testMergePoliciesEmptyInputNeutral = {
    expr = policiesLib.mergePolicies [];
    expected = {
      unfree = [];
      permittedInsecure = [];
    };
  };

  testMergePoliciesConcatenatesLists = {
    expr = policiesLib.mergePolicies [
      {
        unfree = ["a"];
        permittedInsecure = ["b"];
      }
      {
        unfree = ["c"];
        permittedInsecure = ["d"];
      }
    ];
    expected = {
      unfree = ["a" "c"];
      permittedInsecure = ["b" "d"];
    };
  };

  testMergePoliciesPreservesDuplicates = {
    expr = policiesLib.mergePolicies [
      {
        unfree = ["a" "b"];
        permittedInsecure = [];
      }
      {
        unfree = ["b" "c"];
        permittedInsecure = [];
      }
    ];
    expected = {
      unfree = ["a" "b" "b" "c"];
      permittedInsecure = [];
    };
  };

  testMergePoliciesDeterministic = {
    expr = let
      a = policiesLib.mergePolicies [
        {
          unfree = ["a"];
          permittedInsecure = ["b"];
        }
      ];
      b = policiesLib.mergePolicies [
        {
          unfree = ["a"];
          permittedInsecure = ["b"];
        }
      ];
    in
      a == b;
    expected = true;
  };
}
