{flake}: let
  inherit (flake.inputs.nixpkgs) lib;
  fixture = flake.debug.extendModules {
      modules = [
        {
          flake.modules.nixos.adapter-check = {config, ...}: {
            config = lib.mkIf config.local.features.adapter-check.enable {
              environment.variables.ADAPTER_SYSTEM = "enabled";
            };
          };
          flake.modules.homeManager.adapter-check = {config, ...}: {
            config = lib.mkIf config.local.features.adapter-check.enable {
              home.sessionVariables.ADAPTER_HOME = "enabled";
              # Standalone seed defaults already win over these target defaults.
              local.user.email = lib.mkDefault "fallback@example.invalid";
              local.user.stateVersion = lib.mkDefault "24.11";
              local.context.embeddedInNixOS = lib.mkDefault true;
            };
          };
          flake.modules.homeManager.adapter-home-default.local.features.adapter-home-default.enable =
            lib.mkDefault true;
          # Registered Home Manager modules with no host selection.
          flake.modules.homeManager.adapter-unselected-on.local.features.adapter-unselected-on.enable =
            lib.mkDefault true;
          flake.modules.homeManager.adapter-unselected-off.local.features.adapter-unselected-off.enable =
            lib.mkDefault false;
          flake.modules.homeManager.adapter-unselected-empty = {};
          flake.local.featurePolicies.adapter-check = {
            unfree = ["adapter-unfree"];
            permittedInsecure = ["adapter-insecure-1"];
          };

          configurations.nixos = {
            adapter-active.module = {
              imports = [
                ({config, ...}: {
                  config = lib.mkIf config.local.features.adapter-check.enable {
                    environment.variables.ADAPTER_IMPORT = "included";
                    users.users.alice.linger = lib.mkDefault false;
                  };
                })
              ];
              users.users.alice = {
                linger = true;
                openssh.authorizedKeys.keys = ["fixture-key"];
              };
              home-manager.users.alice.home.sessionVariables.ADAPTER_DIRECT = "direct";
              local.context.flakePath = "/fixture";
              local.context.systemStateVersion = "24.05";
              local.users.alice = {
                context = {
                  isAdmin = true;
                  email = "alice@example.invalid";
                  homeDirectory = "/fixture/alice";
                  homeStateVersion = "25.11";
                };
                features = {
                  adapter-check.enable = lib.mkDefault false;
                  adapter-home-default.enable = false;
                };
              };
            };
            adapter-conflict.module = {
              local.features.adapter-check.enable = false;
              local.users.alice.features.adapter-check.enable = true;
            };
            adapter-disabled.module.local = {
              context.systemStateVersion = null;
              users.alice = {
                enable = false;
                features.adapter-check.enable = true;
              };
            };
          };

          configurations.homeManager.adapter-standalone.module = {
            local.features.adapter-check.enable = true;
            local.features.nh.enable = true;
            local.user = {
              name = "alice";
              homeDirectory = "/fixture/alice";
            };
            local.context.homeConfigurationName = "adapter-standalone";
            home = {
              username = "alice";
              homeDirectory = "/fixture/alice";
              stateVersion = "25.11";
            };
          };
        }
        {
          # A second contribution to the same registered aspect.
          flake.modules.homeManager.adapter-check = {config, ...}: {
            config = lib.mkIf config.local.features.adapter-check.enable {
              home.sessionVariables.ADAPTER_EXTRA = "included";
            };
          };
          configurations.nixos.adapter-active.module.local.users.alice.features.adapter-check.enable =
            lib.mkForce true;
          configurations.nixos.adapter-active.module.local.context.systemStateVersion =
            lib.mkDefault "23.11";
        }
      ];
    };
  outputs = fixture.config.flake;
  active = outputs.nixosConfigurations.adapter-active;
  conflict = outputs.nixosConfigurations.adapter-conflict.config;
  disabledHost = outputs.nixosConfigurations.adapter-disabled;
  disabled = disabledHost.config;
  embedded = active.config.home-manager.users.alice;
  standalone = outputs.homeConfigurations.adapter-standalone.config;
  nativeStateVersion = definition:
    (active.extendModules {
      modules = [{system.stateVersion = definition;}];
    }).config.system.stateVersion;
  crossScopeFailures = config:
    builtins.filter
    (entry:
      !entry.assertion
      && lib.hasPrefix "A Home Manager user enabled feature 'adapter-check'," entry.message)
    config.assertions;
  queryPolicy = config: {
    inherit (config.nixpkgs.config) permittedInsecurePackages;
    allowed = config.nixpkgs.config.allowUnfreePredicate {pname = "adapter-unfree";};
    unrelatedAllowed = config.nixpkgs.config.allowUnfreePredicate {pname = "unrelated";};
  };
  hostSeeds = flake.debug.config.configurations.nixos;
  unknownUserFeatures =
    (flake.debug.extendModules {
      modules = [
        {
          configurations.nixos.adapter-unknown.module.local.users.alice.features.adapter-unregistered.enable = true;
        }
      ];
    }).config.configurations.nixos.adapter-unknown.module.local.users.alice.features;
  activePolicy = {
    permittedInsecurePackages = ["adapter-insecure-1"];
    allowed = true;
    unrelatedAllowed = false;
  };
in {
  failures = lib.runTests ({
    testWorkloadAdmissionFollowsEffectiveHomeFeatures = {
      expr = let
        probe = seed: effective: let
          host = (flake.nixosConfigurations.neko7.extendModules {
            modules = [{
              local.users.tenzyu.features.t3code-neko7.enable = lib.mkForce seed;
              home-manager.users.tenzyu.local.features.t3code-neko7.enable = lib.mkForce effective;
            }];
          }).config;
        in lib.hasInfix "/t3-runtime/bin/t3" host.system.preSwitchChecks.neko7-workload-profiles;
      in {
        nativeEnable = probe false true;
        nativeDisable = probe true false;
      };
      expected = {nativeEnable = true; nativeDisable = false;};
    };

    testSystemStateVersionProjection = {
      expr = {
        native = active.config.system.stateVersion;
        home = embedded.home.stateVersion;
        definitions =
          map (definition: {
            inherit (definition) value;
            projected = lib.hasSuffix "/materializers/options.nix" definition.file;
          })
          active.options.system.stateVersion.definitionsWithLocations;
      };
      expected = {
        native = "24.05";
        home = "25.11";
        definitions = [
          {
            value = "24.05";
            projected = true;
          }
        ];
      };
    };

    testUnsetSystemStateVersionUsesNixpkgsDefault = {
      expr = {
        inherit (disabled.system) stateVersion;
        priority = disabledHost.options.system.stateVersion.highestPrio;
        absent = conflict.system.stateVersion;
      };
      expected = {
        stateVersion = disabledHost.options.system.stateVersion.default;
        priority = (lib.mkOptionDefault null).priority;
        absent = outputs.nixosConfigurations.adapter-conflict.options.system.stateVersion.default;
      };
    };

    testSystemStateVersionNativePriorities = {
      expr = {
        default = nativeStateVersion (lib.mkDefault "23.11");
        same = nativeStateVersion "24.05";
        conflict = (builtins.tryEval (nativeStateVersion "23.11")).success;
        force = nativeStateVersion (lib.mkForce "23.11");
      };
      expected = {
        default = "24.05";
        same = "24.05";
        conflict = false;
        force = "23.11";
      };
    };

    testSystemStateVersionEditorOptions = {
      expr = let
        seedContext = kind: let
          configuration = flake.debug.options.configurations.${kind}.type.getSubOptions ["fixture"];
        in
          (configuration.module.type.getSubOptions []).local.context;
        seedOption = (seedContext "nixos").systemStateVersion;
        targetOption = active.options.local.context.systemStateVersion;
      in {
        seedType = seedOption.type.name;
        targetType = targetOption.type.name;
        acceptsString = seedOption.type.check "24.05";
        acceptsNull = seedOption.type.check null;
        acceptsNumber = seedOption.type.check 2411;
        homeSeed = (seedContext "homeManager") ? systemStateVersion;
        homeTarget = standalone.local.context ? systemStateVersion;
      };
      expected = {
        seedType = "nullOr";
        targetType = "nullOr";
        acceptsString = true;
        acceptsNull = true;
        acceptsNumber = false;
        homeSeed = false;
        homeTarget = false;
      };
    };

    testQemuGuestCapabilityIsExplicitRatherThanHiddenInAProfile = {
      expr = {
        hiddenAliases = lib.intersectLists ["proxmox-guest" "qemu-guest-agent"] (lib.attrNames flake.modules.nixos);
        selected = lib.mapAttrs (_: host: host.config.local.features.qemu-guest-profile.enable) flake.nixosConfigurations;
        agentEnabled = flake.nixosConfigurations.neko7.config.services.qemuGuest.enable;
        virtioAvailable = builtins.all
          (name: builtins.elem name flake.nixosConfigurations.neko7.config.boot.initrd.availableKernelModules)
          ["virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net"];
        virtioEarly = builtins.all
          (name: builtins.elem name flake.nixosConfigurations.neko7.config.boot.initrd.kernelModules)
          ["virtio_balloon" "virtio_console"];
      };
      expected = {
        hiddenAliases = [];
        selected = {neko5 = false; neko6 = false; neko7 = true;};
        agentEnabled = true;
        virtioAvailable = true;
        virtioEarly = true;
      };
    };

    testNeko7SerialConsoleIsHostScoped = {
      expr = lib.mapAttrs (_: host:
        builtins.filter
          (param: builtins.elem param ["console=tty0" "console=ttyS0,115200n8"])
          host.config.boot.kernelParams
      ) flake.nixosConfigurations;
      expected = {
        neko5 = [];
        neko6 = [];
        neko7 = ["console=tty0" "console=ttyS0,115200n8"];
      };
    };

    testGameContainersKeepTheirOwnStateVersion = {
      expr =
        lib.mapAttrs (_: container: container.config.system.stateVersion)
        flake.nixosConfigurations.neko7.config.containers;
      expected = {
        neko7-mc = "26.05";
      };
    };

    testNativeHomeLayoutProjectionPreservesSessionValues = {
      expr = let
        home = flake.nixosConfigurations.neko5.config.home-manager.users.tenzyu;
        vars = home.home.sessionVariables;
        exported = home.systemd.user.sessionVariables;
      in {
        cargo = exported.CARGO_HOME == vars.CARGO_HOME;
        bunCache = exported.BUN_INSTALL_CACHE_DIR == vars.BUN_INSTALL_CACHE_DIR;
        codex = exported.CODEX_HOME == vars.CODEX_HOME;
        dotnet = exported.DOTNET_CLI_HOME == vars.DOTNET_CLI_HOME;
      };
      expected = {
        cargo = true;
        bunCache = true;
        codex = true;
        dotnet = true;
      };
    };

    testHomeMigrationIsReadOnlyBeforeNativeChecks = {
      expr = lib.mapAttrs (_: host: let
        user = host.config.home-manager.users.tenzyu;
        activation = user.home.activation;
        names = map (entry: entry.name) (user.lib.dag.topoSort activation).result;
        relevant = ["checkHomeMigration" "checkLinkTargets" "writeBoundary" "linkGeneration"];
      in {
        order = builtins.filter (name: builtins.elem name relevant) names;
        usesActivationCheck = lib.hasInfix " check --activation" activation.checkHomeMigration.data;
        hasAutomaticMigration = activation ? migrateHomeLayout;
      }) flake.nixosConfigurations;
      expected = lib.genAttrs ["neko5" "neko6" "neko7"] (_: {
        order = ["checkHomeMigration" "checkLinkTargets" "writeBoundary" "linkGeneration"];
        usesActivationCheck = true;
        hasAutomaticMigration = false;
      });
    };

    testMigrationRulesFollowFeatureOwners = {
      expr = let
        projection = selections: let
          user =
            (active.extendModules {
              modules = [{local.users.alice.features = selections;}];
            }).config.home-manager.users.alice;
        in {
          owners = lib.unique (map (rule: rule.owner) user.local.homeMigration.paths);
          hasCheck = user.home.activation ? checkHomeMigration;
          androidHome = user.home.sessionVariables ? ANDROID_USER_HOME;
        };
      in {
        disabled = projection {firefox.enable = false;};
        layout = projection {home-layout.enable = true;};
        android = projection {
          home-layout.enable = true;
          android-mic.enable = true;
        };
      };
      expected = {
        disabled = {owners = []; hasCheck = false; androidHome = false;};
        layout = {owners = ["home-layout"]; hasCheck = true; androidHome = false;};
        android = {owners = ["home-layout" "android-mic"]; hasCheck = true; androidHome = true;};
      };
    };

    testHeldHomeRoutesKeepIntendedTargets = {
        expr = let
          routed =
            (active.extendModules {
              modules = [
                {
                  local.users.alice.features = {
                    common.enable = true;
                    home-layout.enable = true;
                    codex.enable = false;
                    firefox.enable = true;
                    zsh.enable = true;
                    android-mic.enable = true;
                  };
                  home-manager.users.alice = {
                    xdg = {
                      configHome = "/fixture/alice/settings";
                      dataHome = "/fixture/alice/data";
                      stateHome = "/fixture/alice/history";
                    };
                    local.homeMigration.legacyGroups = ["codex" "claude" "go" "zsh" "android-mic"];
                    home.sessionVariables.GOBIN = "/fixture/alice/go/custom-bin";
                    home.sessionVariables.GOMODCACHE = "/fixture/alice/go/custom-mod";
                  };
                }
              ];
            }).config;
          user = routed.home-manager.users.alice;
          rules = user.local.homeMigration.paths;
          rule = group: lib.findFirst (item: item.group == group) null rules;
          route = group: [(rule group).route (rule group).target];
          vars = user.home.sessionVariables;
        in {
          codex = route "codex";
          manualCodex = !user.local.features.codex.enable && vars.CODEX_HOME == "/fixture/alice/.codex";
          claude = route "claude";
          claudeExports = vars ? CLAUDE_CONFIG_DIR || user.systemd.user.sessionVariables ? CLAUDE_CONFIG_DIR;
          go = route "go";
          goConsumers = (rule "go").independentRoutes;
          goBinInPath = builtins.elem vars.GOBIN user.home.sessionPath;
          firefox = route "firefox";
          zsh = route "zsh";
          android = route "android-mic";
          adbHome = vars.ANDROID_USER_HOME;
          codexService = user.systemd.user.sessionVariables.CODEX_HOME;
          hasPreSwitch = routed.system.preSwitchChecks ? home-migration-alice;
          useUserPackages = routed.home-manager.useUserPackages;
          backup = routed.home-manager.backupFileExtension;
        };
        expected = {
          codex = ["/fixture/alice/.codex" "/fixture/alice/data/codex"];
          manualCodex = true;
          claude = ["/fixture/alice/.claude" "/fixture/alice/settings/claude"];
          claudeExports = false;
          go = ["/fixture/alice/go" "/fixture/alice/data/go"];
          goConsumers = {
            GOBIN = "/fixture/alice/go/custom-bin";
            GOMODCACHE = "/fixture/alice/go/custom-mod";
          };
          goBinInPath = true;
          firefox = ["/fixture/alice/settings/mozilla/firefox" "/fixture/alice/settings/mozilla/firefox"];
          zsh = ["/fixture/alice/.zsh_history" "/fixture/alice/history/zsh/history"];
          android = ["/fixture/alice/.android" "/fixture/alice/data/android/.android"];
          adbHome = "/fixture/alice";
          codexService = "/fixture/alice/.codex";
          hasPreSwitch = true;
          useUserPackages = true;
          backup = "hm-backup";
        };
      };

      testNhFlakePathFollowsUserFeature = {
      expr = let
        withNh =
          (active.extendModules {
            modules = [{local.users.alice.features.nh.enable = true;}];
          }).config.home-manager.users.alice;
      in {
        nixToolsEnabled = withNh.local.features.nix-tools.enable;
        withNh = withNh.home.sessionVariables.NH_OS_FLAKE;
        withoutNh = embedded.home.sessionVariables ? NH_OS_FLAKE;
        withoutPath = standalone.home.sessionVariables ? NH_OS_FLAKE;
      };
      expected = {
        nixToolsEnabled = false;
        withNh = "/fixture";
        withoutNh = false;
        withoutPath = false;
      };
    };

    testUserContextEditorOptions = {
      expr = let
        configuration = flake.debug.options.configurations.nixos.type.getSubOptions ["fixture"];
        localOptions = (configuration.module.type.getSubOptions []).local;
        userOptions = localOptions.users.type.getSubOptions ["alice"];
      in
        lib.mapAttrs (_: option: option.type.name) userOptions.context;
      expected = {
        isAdmin = "bool";
        email = "str";
        homeDirectory = "str";
        homeStateVersion = "str";
      };
    };

    testConfiguredHostsAndStandaloneOutput = {
      expr = {
        nixos = builtins.attrNames flake.nixosConfigurations;
        home = builtins.attrNames flake.homeConfigurations;
        standalone = builtins.attrNames outputs.homeConfigurations;
      };
      expected = {
        nixos = ["neko5" "neko6" "neko7"];
        home = [];
        standalone = ["adapter-standalone"];
      };
    };

    testSplitcastCacheIsScopedToEnabledConsumerRoles = {
      expr = lib.mapAttrs (_: host: let
        settings = host.config.nix.settings;
      in {
        urls = builtins.filter (url: lib.hasInfix "/tenzyu/splitcast/releases/download/nix-cache-" url) settings.extra-substituters;
        keys = builtins.filter (key: lib.hasPrefix "splitcast-1:" key) settings.extra-trusted-public-keys;
      }) flake.nixosConfigurations;
      expected = {
        neko5 = {urls = []; keys = [];};
        neko6 = {urls = []; keys = [];};
        neko7 = {
          urls = ["https://github.com/tenzyu/splitcast/releases/download/nix-cache-b6fcf1588fec4c42b0e22df58f3bca53c2f51b6f-45916419238-1"];
          keys = ["splitcast-1:vTbhAaBTWjRfVHQekUUYwSb9GBftwHNgBUhXGk0jGwM="];
        };
      };
    };

    testNeko5MakoOwnsSingleBusProvider = {
      expr = let
        home = flake.nixosConfigurations.neko5.config.home-manager.users.tenzyu;
        makoPackages = builtins.filter
          (package: (package.pname or "") == "mako")
          home.home.packages;
      in {
        enabled = home.services.mako.enable;
        noDuplicateHmDbusInstallation = home.services.mako.package == null
          && lib.all
            (package: (package.pname or "") != "mako")
            home.dbus.packages;
        oneUserProfilePackage = builtins.length makoPackages == 1;
        gamemodeMode = home.services.mako.settings."mode=hyprland-gamemode".invisible == 1;
        gamingCliMode = home.services.mako.settings."mode=hyprland-gaming-cli".invisible == 1;
        otherHostsUnselected = lib.all
          (name:
            !flake.nixosConfigurations.${name}.config.home-manager.users.tenzyu.services.mako.enable)
          ["neko6" "neko7"];
      };
      expected = {
        enabled = true;
        noDuplicateHmDbusInstallation = true;
        oneUserProfilePackage = true;
        gamemodeMode = true;
        gamingCliMode = true;
        otherHostsUnselected = true;
      };
    };

    testNeko5SteamProjectsFromUserSelection = {
      expr = let
        seed = hostSeeds.neko5.module.local;
        os = flake.nixosConfigurations.neko5.config;
      in {
        systemSeed = seed.features.steam.enable;
        userSeed = seed.users.tenzyu.features.steam.enable;
        systemFeature = os.local.features.steam.enable;
        systemProgram = os.programs.steam.enable;
        homeFeature = os.home-manager.users.tenzyu.local.features.steam.enable;
      };
      expected = {
        systemSeed = null;
        userSeed = true;
        systemFeature = true;
        systemProgram = true;
        homeFeature = true;
      };
    };

    testNeko5NsncdDoesNotRestartOnResolverUpdates = {
      expr = let
        os = flake.nixosConfigurations.neko5.config;
        conf = os.environment.etc."resolvconf.conf".text;
        # The last assignment wins when openresolv sources resolvconf.conf.
        restartAssignments = builtins.filter
          (line: lib.hasInfix "libc_restart=" line)
          (lib.splitString "\n" conf);
      in {
        nsncdEnabled = os.services.nscd.enable && os.services.nscd.enableNsncd;
        resolverUpdatesEnabled = os.networking.resolvconf.enable;
        policySelected = os.local.features.nsncd-resolver-lifecycle.enable;
        otherHostsUnselected = lib.all
          (name: !flake.nixosConfigurations.${name}.config.local.features.nsncd-resolver-lifecycle.enable)
          ["neko6" "neko7"];
        libcSubscriberEnabled = !(lib.hasInfix "libc=NO" conf);
        cacheInvalidationIsNoop =
          restartAssignments != []
          && lib.hasSuffix "libc_restart=':'" (lib.last restartAssignments);
      };
      expected = {
        nsncdEnabled = true;
        resolverUpdatesEnabled = true;
        policySelected = true;
        otherHostsUnselected = true;
        libcSubscriberEnabled = true;
        cacheInvalidationIsNoop = true;
      };
    };

    testUnregisteredUserFeatureIsRejected = {
      expr = (builtins.tryEval (builtins.deepSeq unknownUserFeatures true)).success;
      expected = false;
    };

    testSshAccessKeysAreScopedToTheirTargetHost = {
      expr = lib.mapAttrs (_: host:
        builtins.any (key: lib.hasSuffix "neko7-to-neko5" key)
        host.config.users.users.tenzyu.openssh.authorizedKeys.keys
      ) flake.nixosConfigurations;
      expected = {
        neko5 = true;
        neko6 = false;
        neko7 = false;
      };
    };

    testNativeOptionOwnershipAndAccessBoundaries = {
      expr = lib.mapAttrs (_: host: let
        hm = host.config.home-manager.users.tenzyu;
      in {
        zshXdgConfig = hm.xdg.configFile ? "zsh/zshrc.d";
        networkmanagerGroup = builtins.elem "networkmanager" host.config.users.users.tenzyu.extraGroups;
        tabletRules = builtins.any
          (pkg: lib.hasInfix "wacom-browser-udev-rules" (toString pkg))
          host.config.services.udev.packages;
      }) flake.nixosConfigurations;
      expected = {
        neko5 = {
          zshXdgConfig = true;
          networkmanagerGroup = true;
          tabletRules = true;
        };
        neko6 = {
          zshXdgConfig = true;
          networkmanagerGroup = false;
          tabletRules = false;
        };
        neko7 = {
          zshXdgConfig = true;
          networkmanagerGroup = false;
          tabletRules = false;
        };
      };
    };

    testHostZshLoginShells = {
      expr =
        lib.mapAttrs (name: host: {
          seed = hostSeeds.${name}.module.local.users.tenzyu.features.zsh.enable;
          native = hostSeeds.${name}.module.home-manager.users.tenzyu.local.features.zsh.enable or null;
          systemFeature = host.config.local.features.zsh.enable;
          systemProgram = host.config.programs.zsh.enable;
          home = host.config.home-manager.users.tenzyu.programs.zsh.enable;
          shell = lib.getName host.config.users.users.tenzyu.shell;
        })
        flake.nixosConfigurations;
      expected = {
        neko5 = {
          seed = true;
          native = null;
          systemFeature = true;
          systemProgram = true;
          home = true;
          shell = "zsh";
        };
        neko6 = {
          seed = null;
          native = true;
          systemFeature = false;
          systemProgram = false;
          home = true;
          shell = "bash-interactive";
        };
        neko7 = {
          seed = true;
          native = null;
          systemFeature = true;
          systemProgram = true;
          home = true;
          shell = "zsh";
        };
      };
    };

    testUserFeatureProjectsAndKeepsDirectOptions = {
      expr = {
        systemFeature = active.config.local.features.adapter-check.enable;
        inherit (active.config.local.users.alice.features.adapter-home-default) enable;
        embeddedDefault = embedded.local.features.adapter-home-default.enable;
        assertions = crossScopeFailures active.config;
        inherit (active.config.environment.variables) ADAPTER_SYSTEM ADAPTER_IMPORT;
        inherit (active.config.home-manager) useGlobalPkgs useUserPackages;
        inherit (active.config.users.users.alice) linger home extraGroups;
        homeDirectory = embedded.home.homeDirectory;
        authorizedKeys = active.config.users.users.alice.openssh.authorizedKeys.keys;
        inherit (embedded.home.sessionVariables) ADAPTER_HOME ADAPTER_EXTRA ADAPTER_DIRECT;
        inherit (embedded.local) user context;
      };
      expected = {
        systemFeature = true;
        enable = false;
        embeddedDefault = false;
        assertions = [];
        ADAPTER_SYSTEM = "enabled";
        ADAPTER_IMPORT = "included";
        useGlobalPkgs = true;
        useUserPackages = true;
        linger = true;
        home = "/fixture/alice";
        homeDirectory = "/fixture/alice";
        extraGroups = ["wheel"];
        authorizedKeys = ["fixture-key"];
        ADAPTER_HOME = "enabled";
        ADAPTER_EXTRA = "included";
        ADAPTER_DIRECT = "direct";
        user = {
          name = "alice";
          email = "alice@example.invalid";
          homeDirectory = "/fixture/alice";
          stateVersion = "25.11";
        };
        context = {
          flakePath = "/fixture";
          hostName = "adapter-active";
          nixosConfigurationName = "adapter-active";
          homeConfigurationName = "alice@adapter-active";
          embeddedInNixOS = true;
        };
      };
    };

    testEmbeddedHomeTriStateNativeDefaults = {
      expr = {
        unselectedOn = embedded.local.features.adapter-unselected-on.enable;
        unselectedOff = embedded.local.features.adapter-unselected-off.enable;
        unselectedEmpty = embedded.local.features.adapter-unselected-empty.enable;
        explicitFalse = embedded.local.features.adapter-home-default.enable;
        explicitTrue = embedded.local.features.adapter-check.enable;
        selectedNull = fixture.config.configurations.nixos.adapter-active.module.local.users.alice.features.adapter-unselected-on.enable;
        selectedFalse = fixture.config.configurations.nixos.adapter-active.module.local.users.alice.features.adapter-home-default.enable;
      };
      expected = {
        unselectedOn = true;
        unselectedOff = false;
        unselectedEmpty = false;
        explicitFalse = false;
        explicitTrue = true;
        selectedNull = null;
        selectedFalse = false;
      };
    };

    testEmbeddedHomeNativePriorities = {
      expr = let
        withModule = module:
          (active.extendModules {modules = [module];}).config.home-manager.users.alice.local.features;
      in {
        forceOverExplicitFalse =
          (withModule {home-manager.users.alice.local.features.adapter-home-default.enable = lib.mkForce true;})
          .adapter-home-default.enable;
        forceOverExplicitTrue =
          (withModule {home-manager.users.alice.local.features.adapter-check.enable = lib.mkForce false;})
          .adapter-check.enable;
        normalTrueConflictsWithFalse =
          (builtins.tryEval (
            (withModule {home-manager.users.alice.local.features.adapter-home-default.enable = true;})
            .adapter-home-default.enable
          )).success;
        normalFalseConflictsWithTrue =
          (builtins.tryEval (
            (withModule {home-manager.users.alice.local.features.adapter-check.enable = false;})
            .adapter-check.enable
          )).success;
      };
      expected = {
        forceOverExplicitFalse = true;
        forceOverExplicitTrue = false;
        normalTrueConflictsWithFalse = false;
        normalFalseConflictsWithTrue = false;
      };
    };

    testEmbeddedHomeRespectsNativeUserEvaluation = {
      expr = let
        withModule = module:
          (active.extendModules {modules = [module];}).config.home-manager.users.alice.local.features;
      in {
        forceTrueOverSeedFalse =
          (withModule {local.users.alice.features.adapter-home-default.enable = lib.mkForce true;})
          .adapter-home-default.enable;
        forceFalseOverSeedTrue =
          (withModule {local.users.alice.features.adapter-check.enable = lib.mkForce false;})
          .adapter-check.enable;
        nativePositiveWithoutHostSelection =
          (withModule {local.users.alice.features.adapter-unselected-empty.enable = lib.mkDefault true;})
          .adapter-unselected-empty.enable;
        nativeFalseWithoutHostSelectionDoesNotSuppressHmDefault =
          (withModule {local.users.alice.features.adapter-unselected-on.enable = lib.mkForce false;})
          .adapter-unselected-on.enable;
      };
      expected = {
        forceTrueOverSeedFalse = true;
        forceFalseOverSeedTrue = false;
        nativePositiveWithoutHostSelection = true;
        nativeFalseWithoutHostSelectionDoesNotSuppressHmDefault = true;
      };
    };

    testNeko5SteamDependencyRemainsSoftDefault = {
      expr = let
        host = flake.nixosConfigurations.neko5;
        off = (host.extendModules {
          modules = [{local.features.gaming-core.enable = false;}];
        }).config;
      in {
        system = host.config.local.features.gaming-core.enable;
        home = host.config.home-manager.users.tenzyu.local.features.gaming-core.enable;
        hostSystemChoice = hostSeeds.neko5.module.local.features.gaming-core.enable;
        hostHomeChoice = hostSeeds.neko5.module.local.users.tenzyu.features.gaming-core.enable;
        explicitSystemOff = off.local.features.gaming-core.enable;
      };
      expected = {
        system = true;
        home = true;
        hostSystemChoice = null;
        hostHomeChoice = null;
        explicitSystemOff = false;
      };
    };

    testSopsUsesProvisionedAgeIdentityOnNeko5AndNeko7 = {
      expr = lib.genAttrs ["neko5" "neko7"] (host: let
        inherit (flake.nixosConfigurations.${host}) config;
      in {
        enabled = config.local.features.sops-nix.enable;
        inherit (config.sops.age) keyFile generateKey sshKeyPaths;
        gnupgSshKeyPaths = config.sops.gnupg.sshKeyPaths;
      });
      expected = lib.genAttrs ["neko5" "neko7"] (_: {
        enabled = true;
        keyFile = "/var/lib/sops-nix/key.txt";
        generateKey = false;
        sshKeyPaths = [];
        gnupgSshKeyPaths = [];
      });
    };

    testMinecraftCanonicalDataAndProtection = {
      expr = let
        host = flake.nixosConfigurations.neko7.config;
        guest = host.containers.neko7-mc.config;
      in {
        data = guest.services.minecraft-servers.dataDir;
        protectHome = guest.systemd.services.minecraft-server-survival.serviceConfig.ProtectHome;
      };
      expected = {data = "/srv/minecraft"; protectHome = true;};
    };

    testGameServerCapabilitiesAreIndependentlySelected = {
      expr = let
        host = flake.nixosConfigurations.neko7.config;
      in {
        ark = host.local.features.game-ark.enable;
        rust = host.local.features.game-rust.enable;
        minecraft = host.local.features.game-minecraft.enable;
        tools = host.local.features.game-server-tools.enable;
        containerNames = lib.attrNames host.containers;
        minecraftAutoStart = host.containers.neko7-mc.autoStart;
        natEnabled = host.networking.nat.enable;
        externalInterface = host.networking.nat.externalInterface;
        minecraftVethPresent = lib.elem "ve-neko7-mc" host.networking.nat.internalInterfaces;
        disabledVethsAbsent = lib.all (name: !(lib.elem name host.networking.nat.internalInterfaces)) [
          "ve-neko7-ark"
          "ve-neko7-rust"
        ];
      };
      expected = {
        ark = false;
        rust = false;
        minecraft = true;
        tools = true;
        containerNames = ["neko7-mc"];
        minecraftAutoStart = true;
        natEnabled = true;
        externalInterface = "ens18";
        minecraftVethPresent = true;
        disabledVethsAbsent = true;
      };
    };

    testNativeForceOverridesCompactedSeed = {
      expr =
        (active.extendModules {
          modules = [
            {
              local.users.alice.features.adapter-check.enable = lib.mkForce false;
            }
          ];
        }).config.local.features.adapter-check.enable;
      expected = false;
    };

    testSystemFalseRejectsUserFeature = {
      expr = {
        enable = conflict.local.features.adapter-check.enable;
        assertions = map (entry: entry.assertion) (crossScopeFailures conflict);
        assertionCheck =
          (builtins.tryEval (
            lib.asserts.checkAssertWarn (crossScopeFailures conflict) [] true
          )).success;
      };
      expected = {
        enable = false;
        assertions = [false];
        assertionCheck = false;
      };
    };

    testDisabledUserDoesNotMaterialize = {
      expr = {
        systemFeature = disabled.local.features.adapter-check.enable;
        account = disabled.users.users ? alice;
        group = disabled.users.groups ? alice;
        home = disabled.home-manager.users ? alice;
        assertions = crossScopeFailures disabled;
      };
      expected = {
        systemFeature = false;
        account = false;
        group = false;
        home = false;
        assertions = [];
      };
    };

    testPackagePolicyAndOverlays = {
      expr = {
        active = queryPolicy active.config;
        standalone = queryPolicy standalone;
        disabled = queryPolicy disabled;
        overlays = lib.filter (name: builtins.hasAttr name active.pkgs) ["llm-agents" "unstable"];
      };
      expected = {
        active = activePolicy;
        standalone = activePolicy;
        disabled = {
          permittedInsecurePackages = [];
          allowed = false;
          unrelatedAllowed = false;
        };
        overlays = ["llm-agents" "unstable"];
      };
    };

    testStandaloneHomeOptions = {
      expr = {
        inherit (standalone.home) username homeDirectory stateVersion preferXdgDirectories;
        inherit (standalone.local) user context;
        inherit (standalone.home.sessionVariables) ADAPTER_HOME ADAPTER_EXTRA;
        xdg = standalone.xdg.enable;
        homeManager = standalone.programs.home-manager.enable;
      };
      expected = {
        username = "alice";
        homeDirectory = "/fixture/alice";
        stateVersion = "25.11";
        preferXdgDirectories = true;
        user = {
          name = "alice";
          email = "";
          homeDirectory = "/fixture/alice";
          stateVersion = "26.05";
        };
        context = {
          flakePath = null;
          hostName = null;
          nixosConfigurationName = null;
          homeConfigurationName = "adapter-standalone";
          embeddedInNixOS = false;
        };
        ADAPTER_HOME = "enabled";
        ADAPTER_EXTRA = "included";
        xdg = true;
        homeManager = true;
      };
    };
  } // import ./native-policy.nix {inherit flake lib;});
}
