{...}: {
  flake.modules.nixos.game-server-containers = { config, lib, pkgs, ... }:
    let
      spec = {
        key = "ark";
        user = "game-ark";
        uid = 27007;
        gid = 27007;
        home = "/home/game-ark";
        containerName = "neko7-ark";
        hostAddress = "10.77.10.1";
        localAddress = "10.77.10.2";
        tailscaleHostname = "neko7-ark";

        udpPorts = [
          7777
          7778
          27015
        ];

        tcpPorts = [
          # ARK RCON / optional browser RCON UI.
          # Tailscale policy should expose these to owner/admin only.
          27020
          4326
          4327
        ];
      };
      inherit (import ./_internal/container.nix { inherit lib pkgs; }) mkGame;
    mkArkModule = spec: {
      lib,
      pkgs,
      ...
    }: let
      home = spec.home;
      installDir = "${home}/ark/server";
      backupDir = "${home}/ark/backups";
      envFile = "${home}/secrets/ark.env";
      serverBinary = "${installDir}/ShooterGame/Binaries/Linux/ShooterGameServer";
    in {
      environment.systemPackages = with pkgs; [
        python3
        steamcmd
        steam-run
      ];

      systemd.services.ark-survival-evolved = {
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
          chmod 0750 ${home} ${home}/ark ${installDir} ${backupDir}
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

      systemd.services.ark-survival-evolved-update = {
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
          chmod 0750 ${home} ${home}/ark ${installDir} ${backupDir}

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


    in {
      config = lib.mkIf config.local.features.game-server-containers.enable
        (mkGame spec mkArkModule);
    };
}
