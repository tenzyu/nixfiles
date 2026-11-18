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
              local.users.alice = {
                isAdmin = true;
                email = "alice@example.invalid";
                homeDirectory = "/fixture/alice";
                homeStateVersion = "25.11";
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
            adapter-disabled.module.local.users.alice = {
              enable = false;
              features.adapter-check.enable = true;
            };
          };

          configurations.homeManager.adapter-standalone.module = {
            local.features.adapter-check.enable = true;
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
        }
      ];
    }).config.flake;
  active = outputs.nixosConfigurations.adapter-active;
  conflict = outputs.nixosConfigurations.adapter-conflict.config;
  disabled = outputs.nixosConfigurations.adapter-disabled.config;
  embedded = active.config.home-manager.users.alice;
  standalone = outputs.homeConfigurations.adapter-standalone.config;
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
  activePolicy = {
    permittedInsecurePackages = ["adapter-insecure-1"];
    allowed = true;
    unrelatedAllowed = false;
  };
in {
  failures = lib.runTests {
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

    testUserFeatureProjectsAndKeepsDirectOptions = {
      expr = {
        systemFeature = active.config.local.features.adapter-check.enable;
        inherit (active.config.local.users.alice.features.adapter-home-default) enable;
        embeddedDefault = embedded.local.features.adapter-home-default.enable;
        assertions = crossScopeFailures active.config;
        inherit (active.config.environment.variables) ADAPTER_SYSTEM ADAPTER_IMPORT;
        inherit (active.config.home-manager) useGlobalPkgs useUserPackages;
        inherit (active.config.users.users.alice) linger extraGroups;
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
