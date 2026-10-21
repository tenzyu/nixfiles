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
        map (file: "${config.home.homeDirectory}/${file.target}")
        (lib.filter (file: file.enable) (builtins.attrValues config.home.file));
    });
    runner = pkgs.writeShellScript "home-layout-migrate" ''
      exec ${pkgs.python3}/bin/python3 ${../../assets/home-layout/migrate.py} \
        --manifest ${manifest} "$@"
    '';
  in {
    # All registry modules are imported. Rules belong to the feature that changes
    # the location, rather than to a host or a one-shot stateVersion migration.
    options.local.homeMigration.paths = lib.mkOption {
      default = [];
      description = "Ordered, non-overwriting legacy-to-XDG moves for enabled features.";
      type = lib.types.listOf (lib.types.submodule {
        options = {
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
        };
      });
    };

    config = lib.mkIf (cfg.paths != []) {
      home.activation.checkHomeMigration = lib.hm.dag.entryBefore ["writeBoundary" "checkLinkTargets"] ''
        ${runner} check
      '';
      home.activation.migrateHomeLayout = lib.hm.dag.entryBetween ["linkGeneration" "installPackages"] ["writeBoundary"] ''
        if [[ -v DRY_RUN ]]; then
          ${runner} check
        else
          ${runner} apply
        fi
      '';
      # Inspect/migrate the existing home BEFORE a NixOS switch also changes the
      # per-user system profile. No separate executable is added to ~/.local/bin.
      home.extraBuilderCommands = ''
        ln -s ${runner} "$out/home-layout-migrate"
      '';
    };
  };

  perSystem = {pkgs, ...}: {
    checks.home-migration =
      pkgs.runCommand "check-home-migration" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        export PYTHONDONTWRITEBYTECODE=1
        export MIGRATE_SOURCE=${../../assets/home-layout/migrate.py}
        python3 ${../../assets/home-layout/test_migrate.py}
        touch "$out"
      '';
  };
}
