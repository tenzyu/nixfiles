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
