{
  flake.features.game-rcon-node = {};

  flake.features.tailscale-node = {
    options = {lib, ...}: {
      hostname = lib.mkOption {
        type = lib.types.str;
        default = "nixos-container";
      };

      authKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      udpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [];
      };

      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [];
      };
    };

    projections.nixos.payload = {
      feature,
      lib,
      pkgs,
      ...
    }: let
      authKeyFile = feature.settings.authKeyFile;
    in {
      networking.hostName = feature.settings.hostname;
      networking.useHostResolvConf = lib.mkForce false;
      networking.nameservers = [
        "1.1.1.1"
        "8.8.8.8"
      ];

      services.tailscale = {
        enable = true;
        extraSetFlags = ["--netfilter-mode=nodivert"];
      };

      systemd.services.tailscale-autoconnect = lib.mkIf (authKeyFile != null) {
        description = "Authenticate ${feature.settings.hostname} to Tailscale";
        wants = [
          "network-online.target"
          "tailscaled.service"
        ];
        after = [
          "network-online.target"
          "tailscaled.service"
        ];
        path = with pkgs; [
          coreutils
          jq
          tailscale
        ];
        unitConfig.ConditionPathExists = authKeyFile;
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "90s";
        };
        script = ''
          set -euo pipefail

          state="$(
            (tailscale status -json 2>/dev/null || echo '{}') \
              | jq -r '.BackendState // "Unknown"'
          )"

          if [ "$state" = "Running" ]; then
            echo "${feature.settings.hostname} is already authenticated to Tailscale."
            exit 0
          fi

          auth_key="$(tr -d '\r\n' < ${authKeyFile})"

          if [ -z "$auth_key" ]; then
            echo "Empty Tailscale auth key: ${authKeyFile}" >&2
            exit 1
          fi

          tailscale up \
            --auth-key "$auth_key" \
            --hostname "${feature.settings.hostname}" \
            --accept-dns=false
        '';
      };

      networking.firewall.enable = true;
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = feature.settings.udpPorts;
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = feature.settings.tcpPorts;

      environment.systemPackages = with pkgs; [
        bind
        curl
        jq
        netcat
        tailscale
      ];
    };
  };

  flake.features.rust-dedicated = {
    policy.unfree = [
      "steamcmd"
      "steam"
      "steam-run"
      "steam-original"
      "steam-unwrapped"
    ];

    options = {lib, ...}: {
      user = lib.mkOption {
        type = lib.types.str;
        default = "game-rust";
      };

      uid = lib.mkOption {
        type = lib.types.int;
        default = 27008;
      };

      gid = lib.mkOption {
        type = lib.types.int;
        default = 27008;
      };

      home = lib.mkOption {
        type = lib.types.str;
        default = "/home/game-rust";
      };

      installDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/game-rust/rust/server";
      };

      backupDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/game-rust/rust/backups";
      };

      envFile = lib.mkOption {
        type = lib.types.str;
        default = "/home/game-rust/secrets/rust.env";
      };
    };

    projections.nixos.payload = {
      feature,
      pkgs,
      ...
    }: let
      inherit (feature.settings) user uid gid home installDir backupDir envFile;
      serverBinary = "${installDir}/RustDedicated";
    in {
      users.groups.${user}.gid = gid;
      users.users.${user} = {
        isNormalUser = true;
        inherit uid;
        group = user;
        inherit home;
        createHome = true;
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        description = "Rust dedicated server service account";
      };

      environment.systemPackages = with pkgs; [
        steamcmd
        steam-run
      ];

      systemd.services.rust-dedicated = {
        description = "Rust Dedicated Server";
        wantedBy = ["multi-user.target"];
        wants = [
          "network-online.target"
          "tailscaled.service"
        ];
        after = [
          "network-online.target"
          "tailscaled.service"
        ];
        restartIfChanged = false;
        unitConfig.ConditionPathExists = [
          envFile
          serverBinary
        ];
        path = with pkgs; [
          coreutils
          steam-run
        ];
        environment.HOME = home;
        preStart = ''
          set -euo pipefail

          mkdir -p ${installDir} ${backupDir}
          chmod 0750 ${home} ${home}/rust ${installDir} ${backupDir}

          mkdir -p ${home}/.steam/sdk64
          if [ -e ${home}/.local/share/Steam/steamcmd/linux64/steamclient.so ]; then
            ln -sf ${home}/.local/share/Steam/steamcmd/linux64/steamclient.so ${home}/.steam/sdk64/steamclient.so
          fi
        '';
        script = ''
          set -euo pipefail

          : "''${RUST_SERVER_HOSTNAME:=neko7-rust}"
          : "''${RUST_SERVER_DESCRIPTION:=Private Rust server via Tailscale}"
          : "''${RUST_SERVER_URL:=}"
          : "''${RUST_SERVER_HEADER_IMAGE:=}"
          : "''${RUST_SERVER_IDENTITY:=neko7-rust}"
          : "''${RUST_SERVER_PORT:=28015}"
          : "''${RUST_SERVER_QUERY_PORT:=28017}"
          : "''${RUST_RCON_PORT:=28016}"
          : "''${RUST_RCON_PASSWORD:?Set RUST_RCON_PASSWORD in ${envFile}}"
          : "''${RUST_RCON_WEB:=1}"
          : "''${RUST_SERVER_MAX_PLAYERS:=10}"
          : "''${RUST_SERVER_LEVEL:=Procedural Map}"
          : "''${RUST_SERVER_SEED:=12345}"
          : "''${RUST_SERVER_WORLDSIZE:=3000}"
          : "''${RUST_SERVER_SAVE_INTERVAL:=300}"
          : "''${RUST_EXTRA_ARGS:=}"

          cd ${installDir}

          mkdir -p "server/''${RUST_SERVER_IDENTITY}"

          exec steam-run ./RustDedicated \
            -batchmode \
            -nographics \
            +server.ip "0.0.0.0" \
            +server.port "''${RUST_SERVER_PORT}" \
            +server.queryport "''${RUST_SERVER_QUERY_PORT}" \
            +server.level "''${RUST_SERVER_LEVEL}" \
            +server.seed "''${RUST_SERVER_SEED}" \
            +server.worldsize "''${RUST_SERVER_WORLDSIZE}" \
            +server.maxplayers "''${RUST_SERVER_MAX_PLAYERS}" \
            +server.hostname "''${RUST_SERVER_HOSTNAME}" \
            +server.description "''${RUST_SERVER_DESCRIPTION}" \
            +server.url "''${RUST_SERVER_URL}" \
            +server.headerimage "''${RUST_SERVER_HEADER_IMAGE}" \
            +server.identity "''${RUST_SERVER_IDENTITY}" \
            +server.saveinterval "''${RUST_SERVER_SAVE_INTERVAL}" \
            +rcon.port "''${RUST_RCON_PORT}" \
            +rcon.password "''${RUST_RCON_PASSWORD}" \
            +rcon.web "''${RUST_RCON_WEB}" \
            -logfile "${home}/rust/rust-dedicated.log" \
            ''${RUST_EXTRA_ARGS}
        '';
        serviceConfig = {
          User = user;
          Group = user;
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

      systemd.services.rust-dedicated-update = {
        description = "Install or update Rust Dedicated Server";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        path = with pkgs; [
          coreutils
          findutils
          gnutar
          gzip
          steamcmd
        ];
        environment.HOME = home;
        script = ''
          set -euo pipefail

          mkdir -p ${installDir} ${backupDir}
          chmod 0750 ${home} ${home}/rust ${installDir} ${backupDir}

          identity="neko7-rust"
          if [ -f ${envFile} ]; then
            # shellcheck disable=SC1090
            . ${envFile}
            identity="''${RUST_SERVER_IDENTITY:-neko7-rust}"
          fi

          if [ -d ${installDir}/server/"$identity" ]; then
            backup="${backupDir}/server-$identity-$(date +%Y%m%d-%H%M%S).tar.gz"
            tar -C ${installDir}/server -czf "$backup" "$identity"
            find ${backupDir} -type f -name 'server-*.tar.gz' -mtime +14 -delete
          fi

          steamcmd \
            +force_install_dir ${installDir} \
            +login anonymous \
            +app_update 258550 validate \
            +quit

          mkdir -p ${home}/.steam/sdk64
          if [ -e ${home}/.local/share/Steam/steamcmd/linux64/steamclient.so ]; then
            ln -sf ${home}/.local/share/Steam/steamcmd/linux64/steamclient.so ${home}/.steam/sdk64/steamclient.so
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          User = user;
          Group = user;
          WorkingDirectory = home;
          TimeoutStartSec = "45min";
        };
      };
    };

    joins.nixosContainerToHost.payload = {feature, ...}: let
      inherit (feature.settings) user uid gid home;
    in {
      users.groups.${user}.gid = gid;
      users.users.${user} = {
        isNormalUser = true;
        inherit uid;
        group = user;
        inherit home;
        createHome = true;
        hashedPassword = "!";
        description = "Rust container service account";
      };

      systemd.tmpfiles.rules = [
        "d ${home} 0750 ${user} ${user} - -"
        "d ${home}/rust 0750 ${user} ${user} - -"
        "d ${home}/rust/server 0750 ${user} ${user} - -"
        "d ${home}/rust/backups 0750 ${user} ${user} - -"
        "d ${home}/secrets 0700 root root - -"
        "d ${home}/.state 0750 root root - -"
        "d ${home}/.state/tailscale 0700 root root - -"
      ];
    };
  };
}
