{lib}: let
  featuresLib = import ../lib/features.nix {inherit lib;};
  usersLib = import ../lib/users.nix {inherit lib featuresLib;};
in {
  testEnabledUsersExcludesExplicitFalse = {
    expr = usersLib.enabledUsers {
      alice = {enable = false;};
      bob = {enable = true;};
    };
    expected = {
      bob = {enable = true;};
    };
  };

  testEnabledUsersIncludesImplicitEnabled = {
    expr = usersLib.enabledUsers {
      alice = {};
      carol = {enable = true;};
    };
    expected = {
      alice = {};
      carol = {enable = true;};
    };
  };

  testCompactNixosUsersCompactsFeatures = {
    expr = usersLib.compactNixosUsers {
      alice = {
        enable = true;
        isAdmin = false;
        email = "";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {
          hyprland = {enable = true;};
          zsh = {enable = null;};
          x = {};
        };
      };
    };
    expected = {
      alice = {
        enable = true;
        isAdmin = false;
        email = "";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {
          hyprland = {enable = true;};
        };
      };
    };
  };

  testCompactNixosUsersPreservesUserFields = {
    expr = usersLib.compactNixosUsers {
      alice = {
        enable = true;
        isAdmin = false;
        email = "alice@x";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {};
      };
    };
    expected = {
      alice = {
        enable = true;
        isAdmin = false;
        email = "alice@x";
        homeDirectory = "/home/alice";
        homeStateVersion = "26.05";
        features = {};
      };
    };
  };
}
