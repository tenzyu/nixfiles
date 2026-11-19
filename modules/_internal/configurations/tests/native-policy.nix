{flake, lib}: let
  neko5 = flake.nixosConfigurations.neko5;
  neko7 = flake.nixosConfigurations.neko7;
  enabled = neko7.config;
  gameFixture = features: (neko7.extendModules {
    modules = [{local.features = features;}];
  }).config;
  lockDir = "/run/nixfiles-game-locks";
  lockSettings = host: host.systemd.tmpfiles.settings.nixfiles-game-locks or {};
  isInstalled = name: packages: lib.any (pkg: lib.getName pkg == name) packages;
  gameState = host: {
    inherit (host.local) gameOperations;
    lockPaths = lib.attrNames (lockSettings host);
    gamePackage = isInstalled "game" host.environment.systemPackages;
    containerUnit = host.systemd.services ? "container@neko7-mc";
  };
  parsecState = host: let
    home = host.home-manager.users.tenzyu;
  in {
    enabled = home.local.features.parsec.enable;
    policy = home.local.parsecActivation;
    actor = home.home.username;
    activationUser = host.systemd.services.home-manager-tenzyu.serviceConfig.User;
    homeDirectory = home.home.homeDirectory;
    configAfter = home.home.activation.parsecConfig.after or null;
    mappingAfter = home.home.activation.parsecTouchpadGpmap.after or null;
    launcher = isInstalled "parsec-xwayland" home.home.packages;
    desktopEntry = home.xdg.desktopEntries ? parsec-xwayland;
    userUnit = home.systemd.user.services ? parsec;
  };
in {
  testMinecraftNativeOperationIdentity = {
    expr = let
      policy = enabled.local.gameOperations.minecraft;
      guest = enabled.containers.${policy.containerName}.config;
      unit = guest.systemd.services.${lib.removeSuffix ".service" policy.guestUnit}.serviceConfig;
    in {
      inherit (enabled.local) gameOperations;
      rules = lockSettings enabled;
      container = enabled.systemd.services ? ${lib.removeSuffix ".service" policy.containerUnit};
      guestUid = guest.users.users.${unit.User}.uid;
      guestGid = guest.users.groups.${unit.Group}.gid;
      hostUid = enabled.users.users.${policy.archiveUser}.uid;
      hostGid = enabled.users.groups.${policy.archiveUser}.gid;
      guestHasLockSettings = lockSettings guest != {};
      guestMounts = builtins.attrNames enabled.containers.${policy.containerName}.bindMounts;
    };
    expected = {
      gameOperations = {
        ark = null;
        rust = null;
        minecraft = {
          lockPath = "${lockDir}/minecraft.lock";
          containerName = "neko7-mc";
          containerUnit = "container@neko7-mc.service";
          guestUnit = "minecraft-server-survival.service";
          archiveUser = "game-minecraft";
          archiveUid = 27009;
          archiveGid = 27009;
          sourceDir = "/srv/minecraft/survival";
          backupsDir = "/srv/minecraft/backups";
        };
      };
      rules = let
        entry = type: mode: {inherit type mode; user = "root"; group = "wheel"; age = "-"; argument = "";};
      in {
        "${lockDir}".d = entry "d" "0750";
        "${lockDir}/minecraft.lock".f = entry "f" "0440";
      };
      container = true;
      guestUid = 27009;
      guestGid = 27009;
      hostUid = 27009;
      hostGid = 27009;
      guestHasLockSettings = false;
      guestMounts = ["/srv/minecraft" "/var/lib/game-containers/minecraft" "/var/lib/tailscale"];
    };
  };

  testGameLockIdentitySurvivesLayoutsAndSeparatesGames = {
    expr = let
      legacy = gameFixture {game-srv.enable = lib.mkForce false;};
      allGames = gameFixture {
        game-ark.enable = lib.mkForce true;
        game-rust.enable = lib.mkForce true;
      };
    in {
      inherit (legacy.local.gameOperations.minecraft) sourceDir backupsDir;
      sameLockSettings = lockSettings legacy == lockSettings enabled;
      allLockPaths = lib.attrNames (lockSettings allGames);
    };
    expected = {
      sourceDir = "/home/game-minecraft/minecraft/survival";
      backupsDir = "/home/game-minecraft/minecraft/backups";
      sameLockSettings = true;
      allLockPaths = [lockDir "${lockDir}/ark.lock" "${lockDir}/minecraft.lock" "${lockDir}/rust.lock"];
    };
  };

  testGamePolicyOnlyFollowsEffectiveFeatures = {
    expr = {
      toolsOnly = gameState (gameFixture {game-minecraft.enable = lib.mkForce false;});
      containerOnly = gameState (gameFixture {game-server-tools.enable = lib.mkForce false;});
    };
    expected = let
      disabled = {gameOperations = {ark = null; minecraft = null; rust = null;}; lockPaths = [];};
    in {
      toolsOnly = disabled // {gamePackage = true; containerUnit = false;};
      containerOnly = disabled // {gamePackage = false; containerUnit = true;};
    };
  };

  testGamePolicyResistsOverrideAndRejectsArchiveWheelMembership = {
    expr = let
      extend = module: (neko7.extendModules {modules = [module];}).config;
      replaced = extend {local.gameOperations.minecraft.lockPath = lib.mkForce "/tmp/untrusted.lock";};
      wheelMember = extra: lib.any
        (entry: !entry.assertion && lib.hasPrefix "The minecraft archive account" entry.message)
        (extend extra).assertions;
    in {
      override = (builtins.tryEval replaced.local.gameOperations.minecraft.lockPath).success;
      explicitUserMembership = wheelMember {users.users.game-minecraft.extraGroups = ["wheel"];};
      wheelGroupMembership = wheelMember {users.groups.wheel.members = ["game-minecraft"];};
    };
    expected = {override = false; explicitUserMembership = true; wheelGroupMembership = true;};
  };

  testParsecPolicyFollowsEmbeddedHomeManagerAndExistingDAG = {
    expr = let
      disabled = (neko5.extendModules {
        modules = [{
          local.users.tenzyu.features.parsec.enable = lib.mkForce false;
          home-manager.users.tenzyu.local.features.parsec.enable = lib.mkDefault true;
        }];
      }).config;
    in {
      enabled = parsecState neko5.config;
      disabled = parsecState disabled;
    };
    expected = let
      common = {
        actor = "tenzyu";
        activationUser = "tenzyu";
        homeDirectory = "/home/tenzyu";
        userUnit = false;
      };
    in {
      enabled = common // {
        enabled = true;
        policy = {
          directory = ".parsec";
          configFile = "config.json";
          mappingFile = "gpmap.txt";
          mappingId = "06cb,83d7";
          mode = "0600";
        };
        configAfter = ["writeBoundary"];
        mappingAfter = ["writeBoundary"];
        launcher = true;
        desktopEntry = true;
      };
      disabled = common // {
        enabled = false;
        policy = null;
        configAfter = null;
        mappingAfter = null;
        launcher = false;
        desktopEntry = false;
      };
    };
  };
}
