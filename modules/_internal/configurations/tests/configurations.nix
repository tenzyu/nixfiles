{flakeRef}: let
  flake = builtins.getFlake flakeRef;
  inherit (flake.inputs.nixpkgs) lib;
  outputs =
    (flake.debug.extendModules {
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
    }).config.flake;
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
  cliFeatures = [
    "btop"
    "common"
    "fastfetch"
    "fzf"
    "git"
    "neovim"
    "packages-common"
    "starship"
    "yazi"
    "zoxide"
  ];
  desktopFeatures = [
    "chromium"
    "firefox"
    "hyprpaper"
    "kitty"
    "mako"
    "packages-desktop"
    "rofi"
    "waybar"
    "wlogout"
  ];
  trackedFeatures = cliFeatures ++ desktopFeatures;
  expectedEnabled = {
    neko5 = lib.sort builtins.lessThan trackedFeatures;
    neko6 = cliFeatures;
    neko7 = cliFeatures;
  };
  enabledFeatures = features:
    lib.attrNames (lib.filterAttrs (name: feature:
      builtins.elem name trackedFeatures && feature.enable == true)
    features);
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
  failures = lib.runTests {
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

    testGameContainersKeepTheirOwnStateVersion = {
      expr =
        lib.mapAttrs (_: container: container.config.system.stateVersion)
        flake.nixosConfigurations.neko7.config.containers;
      expected = {
        neko7-ark = "26.05";
        neko7-rust = "26.05";
        neko7-mc = "26.05";
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

    testHostsSelectConcreteHomeFeatures = {
      expr =
        lib.mapAttrs (name: host: {
          declared = enabledFeatures hostSeeds.${name}.module.local.users.tenzyu.features;
          effective = enabledFeatures host.config.home-manager.users.tenzyu.local.features;
        })
        flake.nixosConfigurations;
      expected =
        lib.mapAttrs (_: names: {
          declared = names;
          effective = names;
        })
        expectedEnabled;
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

    testRemovedProfilesAreNotRegistered = {
      expr = lib.intersectLists ["tenzyu-cli" "tenzyu-desktop"] (lib.attrNames flake.modules.homeManager);
      expected = [];
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

    testHostUserFeatureDisables = {
      expr =
        lib.mapAttrs (name: host: let
          seed = hostSeeds.${name}.module.local.users.tenzyu.features;
          home = host.config.home-manager.users.tenzyu.local.features;
        in {
          tmux = {
            seed = seed.tmux.enable;
            inherit (home.tmux) enable;
          };
          zed = {
            seed = seed.zed-editor.enable;
            inherit (home.zed-editor) enable;
          };
        })
        flake.nixosConfigurations;
      expected = lib.genAttrs ["neko5" "neko6" "neko7"] (name: {
        tmux = {
          seed = false;
          enable = false;
        };
        zed = {
          seed =
            if name == "neko5"
            then false
            else null;
          enable = false;
        };
      });
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
        embeddedDefault = true;
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
  };
}
