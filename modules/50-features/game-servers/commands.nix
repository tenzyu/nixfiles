{...}: {
  flake.modules.nixos.game-server-tools = {
    config,
    lib,
    pkgs,
    ...
  }: let
    layout = import ../../../lib/service-layout.nix {inherit lib;};
    useSrv = config.local.features.game-srv.enable;
    dirs = name: layout.mkGameDirectories (
      {
        key = name;
        home = if useSrv then "/var/lib/game-containers/${name}" else "/home/game-${name}";
      }
      // lib.optionalAttrs useSrv {gameDir = "/srv/${name}";}
    );
    ark = dirs "ark";
    rust = dirs "rust";
    minecraft = config.local.gameOperations.minecraft or null;
    minecraftOperator = pkgs.callPackage ./_internal/minecraft-backup {policy = minecraft;};
  in {
    config = lib.mkIf config.local.features.game-server-tools.enable {
      environment.shellAliases.g = "game";
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "game";
          runtimeInputs = with pkgs; [bash coreutils gnugrep gnutar gzip sudo systemd];
          text = ''
            export GAME_ARK_DATA=${lib.escapeShellArg "${ark.serverDir}/ShooterGame/Saved"}
            export GAME_RUST_DATA=${lib.escapeShellArg "${rust.serverDir}/server"}
            export GAME_ARK_BACKUPS=${lib.escapeShellArg ark.backupsDir}
            export GAME_RUST_BACKUPS=${lib.escapeShellArg rust.backupsDir}
            readonly minecraft_operator=${lib.escapeShellArg (if minecraft == null then "" else "${minecraftOperator}/bin/minecraft-operator")}
            readonly operator_sudo=${lib.escapeShellArg "${config.security.wrapperDir}/sudo"}
          '' + builtins.readFile ./_internal/game.sh;
        })
      ];
    };
  };
}
