{lib}: let
  features = import ./features.nix {inherit lib;};
  users = import ./users.nix {inherit lib features;};
  policies = import ./policies.nix {inherit lib features;};
  composition = import ./composition.nix {inherit lib;};
  layout = import ./service-layout.nix {inherit lib;};
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

  testNamedDisjointMergeAndProvenance = {
    expr = let
      merged = composition.namedDisjoint {
        label = "project-user";
        layers = [
          {name = "features"; attrs.features.steam.enable = true;}
          {name = "context"; attrs.context.user = "alice";}
          {name = "optional"; attrs = {};}
        ];
      };
    in {
      names = merged.layerNames;
      owners = merged.owners;
      value = merged.merged;
    };
    expected = {
      names = ["features" "context" "optional"];
      owners = {features = "features"; context = "context";};
      value = {features.steam.enable = true; context.user = "alice";};
    };
  };

  testNamedDisjointRejectsCollisionEvenIfOverwrittenValueUnused = {
    expr = {
      overlap = (builtins.tryEval ((composition.namedDisjoint {
        label = "overlap";
        layers = [
          {name = "first"; attrs = {a = 1; b = throw "not forced";};}
          {name = "second"; attrs = {a = 2;};}
        ];
      }).merged.a)).success;
      duplicateLayerName = (builtins.tryEval ((composition.namedDisjoint {
        label = "duplicate";
        layers = [{name = "same"; attrs = {};} {name = "same"; attrs = {};}];
      }).layerNames)).success;
      nonAttrs = (builtins.tryEval ((composition.namedDisjoint {
        label = "invalid";
        layers = [{name = "x"; attrs = 42;}];
      }).layerNames)).success;
    };
    expected = {overlap = false; duplicateLayerName = false; nonAttrs = false;};
  };

  testNamedDisjointDoesNotForceValues = {
    expr = let
      result = composition.namedDisjoint {
        label = "lazy";
        layers = [{name = "one"; attrs = {a = 1; b = throw "never forced";};}];
      };
    in {
      owns = result.owners.b;
      a = result.merged.a;
    };
    expected = {owns = "one"; a = 1;};
  };

  testOverrideExistingRequiresKnownKeys = {
    expr = {
      output = composition.overrideExisting {
        label = "typed-seed";
        base = {name = "alice"; email = "a@example.com";};
        replacements = {name = null;};
      };
      absent = (builtins.tryEval (composition.overrideExisting {
        label = "typo";
        base = {name = "alice";};
        replacements = {naem = "bob";};
      })).success;
    };
    expected = {
      output = {name = null; email = "a@example.com";};
      absent = false;
    };
  };

  testServiceLayoutPreservesLegacyPaths = {
    expr = layout.mkGameDirectories {
      key = "minecraft";
      home = "/home/game-minecraft";
    };
    expected = {
      home = "/home/game-minecraft";
      gameDir = "/home/game-minecraft/minecraft";
      serverDir = "/home/game-minecraft/minecraft/server";
      backupsDir = "/home/game-minecraft/minecraft/backups";
      secretsDir = "/home/game-minecraft/secrets";
      stateDir = "/home/game-minecraft/.state";
      tailscaleDir = "/home/game-minecraft/.state/tailscale";
    };
  };

  testServiceLayoutAllowsIndependentDataRoot = {
    expr = (layout.mkGameDirectories {
      key = "minecraft";
      home = "/var/lib/game-containers/minecraft";
      gameDir = "/srv/minecraft";
    }).gameDir;
    expected = "/srv/minecraft";
  };

  testServiceLayoutRejectsTraversalAndStorePaths = {
    expr = {
      badKey = (builtins.tryEval (layout.mkGameDirectories {
        key = "../minecraft";
        home = "/home/service";
      }).gameDir).success;
      badRoot = (builtins.tryEval (layout.mkGameDirectories {
        key = "minecraft";
        home = "/srv/../tmp";
      }).gameDir).success;
      storeRoot = (builtins.tryEval (layout.mkGameDirectories {
        key = "minecraft";
        home = "/nix/store/example";
      }).gameDir).success;
    };
    expected = {badKey = false; badRoot = false; storeRoot = false;};
  };

  testStaticServiceAccountsAgreeAcrossScopes = {
    expr = let
      account = layout.mkStaticServiceAccount {bashInteractive = "/bin/bash";} {
        key = "minecraft";
        user = "game-minecraft";
        uid = 27009;
        gid = 27009;
        home = "/var/lib/game-containers/minecraft";
        containerName = "neko7-mc";
      };
    in {
      uid = account.users.users.game-minecraft.uid;
      gid = account.users.groups.game-minecraft.gid;
      home = account.users.users.game-minecraft.home;
      isNormalUser = account.users.users.game-minecraft.isNormalUser;
    };
    expected = {
      uid = 27009;
      gid = 27009;
      home = "/var/lib/game-containers/minecraft";
      isNormalUser = true;
    };
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
