{...}: {
  flake.modules.nixos.game-server-tools = {
    config,
    lib,
    pkgs,
    ...
  }: let
    layout = import ../../../lib/service-layout.nix {inherit lib;};
    specs = import ./_internal/specs.nix;
    ark = layout.mkGameOperation specs.ark;
    rust = layout.mkGameOperation specs.rust;
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
            export GAME_ARK_DATA=${lib.escapeShellArg ark.sourceDir}
            export GAME_RUST_DATA=${lib.escapeShellArg rust.sourceDir}
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
