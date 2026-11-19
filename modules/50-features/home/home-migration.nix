{
  flake.modules.homeManager.home-migration = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.local.homeMigration;
    manifest = pkgs.writeText "home-migration.json" (builtins.toJSON {
      home = config.home.homeDirectory;
      state = "${config.xdg.stateHome}/home-cleanup/bronze/activation";
      rules = cfg.paths;
      managed =
        map (file: if lib.hasPrefix "/" file.target then file.target else "${config.home.homeDirectory}/${file.target}")
        (lib.filter (file: file.enable) (builtins.attrValues config.home.file));
    });
    migration = pkgs.callPackage ../../../assets/home-layout {};
    runner = migration.launcher manifest;
  in {
    # All registry modules are imported. Rules belong to the feature that changes
    # the location, rather than to a host or a one-shot stateVersion migration.
    options.local.homeMigration.paths = lib.mkOption {
      default = [];
      description = "Ordered, non-overwriting legacy-to-XDG moves for enabled features.";
      type = lib.types.listOf (lib.types.submodule {
        options = {
          owner = lib.mkOption {type = lib.types.str;};
          source = lib.mkOption {type = lib.types.str;};
          target = lib.mkOption {type = lib.types.str;};
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
      });
    };

    config = lib.mkIf (cfg.paths != []) {
      # Activation is read-only, without an auto-apply escape hatch. A NixOS
      # switch can trigger Home Manager; it must never rename user data.
      # Pending work is advisory; an unsafe plan or native link collision still fails.
      home.activation.checkHomeMigration = lib.hm.dag.entryBefore ["writeBoundary" "checkLinkTargets"] ''
        ${runner} check --activation
      '';
      # Export the reviewable runner for an explicitly authorized, separate
      # operation before a NixOS/Home Manager switch.
      home.extraBuilderCommands = ''
        ln -s ${runner} "$out/home-layout-migrate"
      '';
    };
  };

  perSystem = {pkgs, ...}: let
    migration = pkgs.callPackage ../../../assets/home-layout {};
  in {
    checks.home-migration =
      pkgs.runCommand "check-home-migration" {
        nativeBuildInputs = [pkgs.python3];
        PYTHONPATH = migration.source;
        PYTHONDONTWRITEBYTECODE = "1";
        MIGRATE_LAUNCHER = migration.launcher "/proc/self/fd/0";
      } ''
        python3 ${../../../assets/home-layout/test_migrate.py} -v
        touch "$out"
      '';
  };
}
