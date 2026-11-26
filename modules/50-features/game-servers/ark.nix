{...}: {
  flake.local.featurePolicies.game-ark.unfree = import ./_internal/steam-unfree.nix;
  flake.modules.nixos.game-ark = {
    config,
    lib,
    pkgs,
    ...
  }: let
    layout = import ../../../lib/service-layout.nix {inherit lib;};
    spec = (import ./_internal/specs.nix).ark;
    inherit (import ./_internal/container.nix {inherit config lib pkgs;}) mkGame;
    mkArkModule = spec: {
      lib,
      pkgs,
      ...
    }: let
      d = layout.mkGameDirectories spec;
      home = d.home;
      installDir = d.serverDir;
      backupDir = d.backupsDir;
      envFile = "${d.secretsDir}/ark.env";
      serverBinary = "${installDir}/ShooterGame/Binaries/Linux/ShooterGameServer";
    in {
      environment.systemPackages = with pkgs; [
        python3
        steamcmd
        steam-run
      ];

      systemd.services.${spec.guestService} = {
        description = "ARK: Survival Evolved Dedicated Server";
        wantedBy = ["multi-user.target"];
        wants = [
          "network-online.target"
          "tailscaled.service"
        ];
        after = [
          "network-online.target"
          "tailscaled.service"
        ];

        # Game servers should not restart just because nixos-rebuild changed a unit.
        # Restart explicitly when the game operation says so.
        restartIfChanged = false;

        unitConfig = {
          ConditionPathExists = [
            envFile
            serverBinary
          ];
        };

        path = with pkgs; [
          coreutils
          steam-run
        ];

        environment = {
          HOME = home;
        };

        preStart = ''
          set -euo pipefail

          mkdir -p ${installDir} ${backupDir}
          chmod 0750 ${home} ${d.gameDir} ${installDir} ${backupDir}
        '';

        script = ''
          set -euo pipefail

          : "''${ARK_MAP:=TheIsland}"
          : "''${ARK_SESSION_NAME:=neko7-ark}"
          : "''${ARK_SERVER_PASSWORD:=}"
          : "''${ARK_ADMIN_PASSWORD:?Set ARK_ADMIN_PASSWORD in ${envFile}}"
          : "''${ARK_GAME_PORT:=7777}"
          : "''${ARK_QUERY_PORT:=27015}"
          : "''${ARK_MAX_PLAYERS:=10}"
          : "''${ARK_EXTRA_URL_OPTIONS:=}"
          : "''${ARK_EXTRA_ARGS:=}"

          cd ${installDir}/ShooterGame/Binaries/Linux

          url="''${ARK_MAP}?listen?SessionName=''${ARK_SESSION_NAME}?ServerPassword=''${ARK_SERVER_PASSWORD}?ServerAdminPassword=''${ARK_ADMIN_PASSWORD}?Port=''${ARK_GAME_PORT}?QueryPort=''${ARK_QUERY_PORT}?MaxPlayers=''${ARK_MAX_PLAYERS}''${ARK_EXTRA_URL_OPTIONS}"

          exec steam-run ./ShooterGameServer "$url" -server -log ''${ARK_EXTRA_ARGS}
        '';

        serviceConfig = {
          User = spec.user;
          Group = spec.user;
          WorkingDirectory = home;
          EnvironmentFile = envFile;

          Restart = "on-failure";
          RestartSec = "10s";

          TimeoutStartSec = "5min";
          TimeoutStopSec = "120s";
          KillSignal = "SIGINT";

          LimitNOFILE = 1048576;
        };
      };

      systemd.services."${spec.guestService}-update" = {
        description = "Install or update ARK: Survival Evolved Dedicated Server";
        wants = ["network-online.target"];
        after = ["network-online.target"];

        path = with pkgs; [
          coreutils
          findutils
          gnutar
          gzip
          steamcmd
        ];

        environment = {
          HOME = home;
        };

        script = ''
          set -euo pipefail

          mkdir -p ${installDir} ${backupDir}
          chmod 0750 ${home} ${d.gameDir} ${installDir} ${backupDir}

          if [ -d ${installDir}/ShooterGame/Saved ]; then
            backup="${backupDir}/saved-$(date +%Y%m%d-%H%M%S).tar.gz"
            tar -C ${installDir}/ShooterGame -czf "$backup" Saved
            find ${backupDir} -type f -name 'saved-*.tar.gz' -mtime +14 -delete
          fi

          steamcmd \
            +force_install_dir ${installDir} \
            +login anonymous \
            +app_update 376030 validate \
            +quit
        '';

        serviceConfig = {
          Type = "oneshot";
          User = spec.user;
          Group = spec.user;
          WorkingDirectory = home;
          TimeoutStartSec = "45min";
        };
      };
    };
  in mkGame spec mkArkModule;
}
