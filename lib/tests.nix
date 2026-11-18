{lib}: let
  features = import ./features.nix {inherit lib;};
  users = import ./users.nix {inherit lib features;};
  policies = import ./policies.nix {inherit lib features;};
  composition = import ./composition.nix {inherit lib;};
  pipeline = composition.namedPipeline {
    label = "test.normalization";
    steps = [
      {name = "increment"; run = x: x + 1;}
      {name = "stringify"; run = x: "value-${toString x}";}
    ];
  };
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
  testNamedPipelineNamesAndOrderedEvaluation = {
    expr = {
      names = pipeline.stageNames;
      value = pipeline.run 2;
      empty = (composition.namedPipeline {label = "identity"; steps = [];}).run {a = 1;};
    };
    expected = {
      names = ["increment" "stringify"];
      value = "value-3";
      empty = {a = 1;};
    };
  };

  testNamedPipelineRejectsInvalidStages = {
    expr = {
      duplicate = (builtins.tryEval (
        (composition.namedPipeline {
          label = "duplicate";
          steps = [{name = "x"; run = x: x;} {name = "x"; run = x: x;}];
        }).stageNames
      )).success;
      missingRun = (builtins.tryEval (
        (composition.namedPipeline {
          label = "invalid";
          steps = [{name = "x";}];
        }).stageNames
      )).success;
      blank = (builtins.tryEval (
        (composition.namedPipeline {
          label = "empty-name";
          steps = [{name = ""; run = x: x;}];
        }).stageNames
      )).success;
    };
    expected = {duplicate = false; missingRun = false; blank = false;};
  };

  testNamedPipelinePreservesNativeOptionWrappers = {
    expr = let
      value = (composition.namedPipeline {
        label = "definition-data";
        steps = [{name = "select"; run = x: {config = x.config;};}];
      }).run {config.foo = lib.mkDefault true;};
    in value.config.foo._type;
    expected = "override";
  };

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
