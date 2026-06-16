{lib}: let
  featuresLib = import ../lib/features.nix {inherit lib;};
  usersLib = import ../lib/users.nix {inherit lib featuresLib;};
  seedLib = import ../lib/seed.nix {inherit lib featuresLib usersLib;};
in {
  testCompactContextDropsNulls = {
    expr = seedLib.compactContext {
      a = "x";
      b = null;
      c = "y";
    };
    expected = {
      a = "x";
      c = "y";
    };
  };

  testCompactNixosSeedModuleOmitsAbsentContext = {
    expr = seedLib.compactNixosSeedModule {
      local.features.alpha.enable = true;
    };
    expected = {
      local.features.alpha.enable = true;
      local.users = {};
    };
  };

  testCompactNixosSeedModuleDropsNullContextFields = {
    expr = seedLib.compactNixosSeedModule {
      local.features.alpha.enable = true;
      local.context = {
        a = "x";
        b = null;
      };
    };
    expected = {
      local.features.alpha.enable = true;
      local.users = {};
      local.context = {
        a = "x";
      };
    };
  };

  testCompactNixosSeedModulePreservesExplicitFalseFeature = {
    expr = seedLib.compactNixosSeedModule {
      local.features = {
        alpha = {enable = true;};
        beta = {enable = false;};
        gamma = {enable = null;};
      };
    };
    expected = {
      local.features = {
        alpha = {enable = true;};
        beta = {enable = false;};
      };
      local.users = {};
    };
  };

  testCompactHomeSeedModuleDropsNixosOnlyUsers = {
    expr = seedLib.compactHomeSeedModule {
      local.users.alice.enable = true;
      local.features.alpha.enable = true;
    };
    expected = {
      local.features.alpha.enable = true;
    };
  };

  testCompactHomeSeedModulePreservesHmFields = {
    expr = seedLib.compactHomeSeedModule {
      local.user = {
        name = "alice";
        email = "alice@x";
        homeDirectory = "/home/alice";
        stateVersion = "26.05";
      };
      local.context.hostName = "neko5";
    };
    expected = {
      local.user = {
        name = "alice";
        email = "alice@x";
        homeDirectory = "/home/alice";
        stateVersion = "26.05";
      };
      local.context.hostName = "neko5";
    };
  };
}
