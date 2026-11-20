{
  inputs,
  config,
  ...
}: let
  configModules = config.flake.modules.homeManager;
in {
  flake.modules.homeManager.home-migration = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.local.homeMigration;
    home = config.home.homeDirectory;
    groupNames = lib.unique (map (rule: rule.group) cfg.paths);
    absolute = path:
      if lib.hasPrefix "/" path
      then path
      else "${home}/${path}";
    # These pinned HM entries manage the generation/profile, create directories,
    # or reload the user manager. The file entries have their own concrete checks.
    nativeSteps = [
      "checkHomeMigration"
      "checkLinkTargets"
      "checkFilesChanged"
      "writeBoundary"
      "linkGeneration"
      "installPackages"
      "onFilesChange"
      "createXdgUserDirectories"
      "reloadSystemd"
      "checkKittyTheme"
    ];
    knownWrites =
      {
        parsecConfig = [".parsec"];
        parsecTouchpadGpmap = [".parsec"];
        updateLocalMimeDatabase = ["${config.xdg.dataHome}/mime"];
        dconfSettings = ["${config.xdg.configHome}/dconf"];
        reloadPipewire = [];
      }
      // cfg.activationWrites;
    extraSteps = lib.subtractLists nativeSteps (builtins.attrNames config.home.activation);
    files = lib.filter (file: file.enable) (builtins.attrValues config.home.file);
    managed = map (file: absolute file.target) files;
    manifest = pkgs.writeText "home-migration.json" (builtins.toJSON {
      version = 2;
      inherit home managed;
      host = config.local.context.hostName or null;
      stateHome = config.xdg.stateHome;
      state = "${config.xdg.stateHome}/home-cleanup/bronze/activation";
      externalBases = with config.xdg; [cacheHome configHome dataHome stateHome];
      rules = map (rule:
        rule
        // {
          serviceRoutes =
            builtins.intersectAttrs
            (lib.genAttrs (rule.serviceVariables ++ builtins.attrNames rule.independentRoutes) (_: null))
            config.systemd.user.sessionVariables;
        })
      cfg.paths;
      adopt = cfg.adoptedRoutes;
      reconciled = cfg.reconciledGroups;
      activationWrites = map absolute (lib.concatMap (name: knownWrites.${name} or []) extraSteps);
      opaque =
        lib.filter (name: !builtins.hasAttr name knownWrites) extraSteps
        ++ map (file: "onChange:${file.target}") (lib.filter (file: file.onChange != "") files);
    });
    migration = pkgs.callPackage ../../../assets/home-layout {};
    runner = migration.launcher manifest;
    preSwitch = pkgs.writeShellScript "home-layout-pre-switch" ''
      set -eu
      newGenPath="$1"
      shift
      ${runner} check --admission --generation "$newGenPath" "$@"
      export PATH=${lib.makeBinPath [pkgs.bash pkgs.coreutils pkgs.findutils pkgs.diffutils]}
      ${config.home.activation.checkLinkTargets.data}
    '';
  in {
    options.local.homeMigration = {
      legacyGroups = lib.mkOption {
        default = [];
        type = lib.types.listOf lib.types.str;
        description = "Enabled migration groups whose verified incumbent is the legacy route.";
      };
      adoptedRoutes = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (lib.types.enum ["legacy" "intended"]);
        description = "Incumbent routes verified by read-only inventory before first adoption.";
      };
      reconciledGroups = lib.mkOption {
        default = [];
        type = lib.types.listOf lib.types.str;
        description = "Groups with independently approved app-native reconciliation and reversible retirement of their legacy names.";
      };
      activationWrites = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        description = "Reviewed write roots of additional Home Manager activation entries, relative to HOME or absolute.";
      };
      paths = lib.mkOption {
        default = [];
        description = "Ordered, non-overwriting legacy-to-XDG moves for enabled features.";
        type = lib.types.listOf (lib.types.submodule ({config, ...}: {
          options = {
            owner = lib.mkOption {type = lib.types.str;};
            group = lib.mkOption {
              type = lib.types.str;
              default = config.owner;
            };
            source = lib.mkOption {type = lib.types.str;};
            target = lib.mkOption {type = lib.types.str;};
            route = lib.mkOption {
              type = lib.types.str;
              default = config.target;
            };
            consumers = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
            };
            serviceVariables = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
            };
            independentRoutes = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
            };
            processes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
            };
            references = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "JSON/TOML files containing references to this application's old root.";
            };
            repairAbsoluteLinks = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Diagnose absolute symlinks pointing to a declared legacy migration root.";
            };
          };
        }));
      };
    };

    config = lib.mkMerge [
      {
        assertions = [
          {
            assertion =
              lib.length (lib.unique cfg.legacyGroups)
              == lib.length cfg.legacyGroups
              && lib.length (lib.unique cfg.reconciledGroups) == lib.length cfg.reconciledGroups
              && lib.intersectLists cfg.legacyGroups cfg.reconciledGroups == []
              && lib.all (group: builtins.elem group groupNames)
              (cfg.legacyGroups ++ cfg.reconciledGroups ++ builtins.attrNames cfg.adoptedRoutes);
            message = "homeMigration records must name enabled groups, with unique, disjoint hold and reconciliation lists.";
          }
        ];
        home.extraBuilderCommands = ''
          ln -s ${manifest} "$out/home-layout-manifest.json"
          ln -s ${runner} "$out/home-layout-migrate"
          ln -s ${preSwitch} "$out/home-layout-pre-switch"
        '';
      }
      (lib.mkIf (cfg.paths != []) {
        home.activation.checkHomeMigration = lib.hm.dag.entryBefore ["writeBoundary" "checkLinkTargets"] ''
          ${runner} check --activation --generation "$newGenPath" --previous "''${oldGenPath:-}"
        '';
      })
    ];
  };

  perSystem = {pkgs, ...}: let
    migration = pkgs.callPackage ../../../assets/home-layout {};
    crossMountFixture = pkgs.writeShellScript "home-migration-cross-mount-fixture" ''
      set -eu
      export PATH=${pkgs.lib.makeBinPath [pkgs.coreutils pkgs.rsync pkgs.acl]}
      export HOME=/home/hfixture TMPDIR=/var/tmp NIXFILES_CROSS_MOUNT=/migration-target
      export PYTHONPATH=${migration.source} PYTHONDONTWRITEBYTECODE=1 NIXFILES_REQUIRE_CROSS_MOUNT=1
      export MIGRATE_LAUNCHER=${migration.launcher "/proc/self/fd/0"}
      test -d "$NIXFILES_CROSS_MOUNT"
      test -w "$NIXFILES_CROSS_MOUNT"
      rsync --version >/dev/null
      exec ${pkgs.python3}/bin/python3 ${../../../assets/home-layout/test_migrate.py} -k cross_mount -v
    '';
    embedded = pkgs.testers.runNixOSTest {
      name = "home-migration-embedded";
      requiredFeatures.kvm = false;
      nodes.machine = {
        config,
        lib,
        pkgs,
        ...
      }: let
        user = "hfixture";
        home = "/home/${user}";
        owner = {
          context = {
            email = "fixture@example.invalid";
            homeDirectory = home;
            homeStateVersion = "26.05";
          };
          features = {};
        };
        profile = variant:
          pkgs.writeShellScriptBin "fixture-app" ''
            set -eu
            root="''${CODEX_HOME:-$HOME/.codex}"
            case "$1" in
              version) printf '%s\n' ${variant} ;;
              read) cat "$root/record" ;;
              save) printf '%s\n' "$2" >> "$root/record" ;;
            esac
          '';
        variant = name: {
          home-manager.users.${user} = {lib, ...}: {
            local.homeMigration.legacyGroups =
              lib.mkForce (lib.optional (!builtins.elem name ["intended" "redirected"]) "codex");
            xdg.dataHome = lib.mkIf (name == "redirected") (lib.mkForce "${home}/redirected-data");
            local.fixtureVariant = lib.mkForce name;
            home.file =
              {
                ".codex/old-link".enable = lib.mkForce false;
              }
              // lib.optionalAttrs (builtins.elem name ["backup" "forced"]) {
                ".codex/record" = {
                  text = "managed replacement";
                  force = name == "forced";
                };
              }
              // lib.optionalAttrs (name == "intended") {
                ".local/share/codex/new-link".text = "intended fragment";
              }
              // lib.optionalAttrs (name == "held") {
                "unrelated.txt".text = "held generation";
              };
            home.activation.fixtureSentinel = lib.mkForce (lib.hm.dag.entryAfter ["linkGeneration"] ''
              run ${pkgs.coreutils}/bin/touch "$HOME/reached-${name}"
            '');
            local.homeMigration.activationWrites.fixtureSentinel = lib.mkForce ["reached-${name}"];
          };
        };
      in {
        imports = [
          inputs.home-manager.nixosModules.home-manager
          (import ../../_internal/configurations/materializers/home-manager.nix {
            homeFeatureOptionsModule = {
              options.local = {
                user = lib.mkOption {type = lib.types.attrs;};
                context = lib.mkOption {type = lib.types.attrs;};
                features.home-layout.enable = lib.mkEnableOption "fixture home layout";
                fixtureVariant = lib.mkOption {
                  type = lib.types.str;
                  default = "initial";
                };
              };
            };
            homeModuleList = [configModules.home-migration configModules.home-layout];
            embeddedHomeFeatures = _: _: {home-layout.enable = true;};
            enabledUsers = lib.id;
          } {})
          {
            options.local = {
              users = lib.mkOption {type = lib.types.attrs;};
              context = lib.mkOption {type = lib.types.attrs;};
            };
          }
        ];
        _module.args.helpers = {};
        local = {
          users.${user} = owner;
          context = {
            flakePath = null;
            hostName = "machine";
            nixosConfigurationName = "machine";
          };
        };
        users.users.${user} = {
          isNormalUser = true;
          uid = 1000;
        };
        home-manager.users.${user} = {
          config,
          lib,
          ...
        }: {
          local.homeMigration = {
            legacyGroups = ["codex"];
            adoptedRoutes.codex = "legacy";
            activationWrites.fixtureSentinel = ["reached-initial"];
          };
          home.packages = [(profile config.local.fixtureVariant)];
          home.file.".codex/old-link".text = "old generation fragment";
          home.activation.fixtureSentinel = lib.hm.dag.entryAfter ["linkGeneration"] ''
            run ${pkgs.coreutils}/bin/touch "$HOME/reached-initial"
          '';
          systemd.user.services.fixture-read = {
            Unit.Description = "Fixture consumer of the Home Manager user environment";
            Service = {
              Type = "oneshot";
              ExecStart = "${config.home.profileDirectory}/bin/fixture-app read";
              StandardOutput = "append:${home}/unit-read";
            };
          };
        };
        specialisation = lib.genAttrs ["held" "intended" "redirected" "backup" "forced"] (name: {configuration = variant name;});
        environment.systemPackages = [pkgs.jq];
        boot.tmp.useTmpfs = false;
        virtualisation.fileSystems."/migration-target" = {
          device = "tmpfs";
          fsType = "tmpfs";
          options = ["mode=0700" "uid=1000" "size=64M"];
        };
        virtualisation.memorySize = 1536;
        system.stateVersion = "26.05";
      };
      testScript = ''
        machine.start()
        machine.wait_for_unit("home-manager-hfixture.service")
        machine.succeed("bash ${../../../assets/home-layout/test-activation.sh}")
        machine.succeed("${pkgs.util-linux}/bin/findmnt --noheadings --mountpoint /migration-target --types tmpfs")
        machine.succeed("runuser -u hfixture -- ${crossMountFixture}")
      '';
    };
    engine =
      pkgs.runCommand "check-home-migration-engine" {
        nativeBuildInputs = [pkgs.python3 pkgs.rsync];
        PYTHONPATH = migration.source;
        PYTHONDONTWRITEBYTECODE = "1";
        MIGRATE_LAUNCHER = migration.launcher "/proc/self/fd/0";
      } ''
        python3 ${../../../assets/home-layout/test_migrate.py} -v
        touch "$out"
      '';
  in {
    checks.home-migration = pkgs.runCommand "check-home-migration" {} ''
      test -e ${engine} && test -e ${embedded}
      touch "$out"
    '';
  };
}
