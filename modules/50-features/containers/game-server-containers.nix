{
  flake.local.featurePolicies.game-server-containers.unfree = [
    "steamcmd"
    "steam"
    "steam-run"
    "steam-original"
    "steam-unwrapped"
  ];

  flake.modules.nixos.game-server-containers = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) concatLists mapAttrsToList mkIf mkMerge;

    # Confirmed on neko7:
    #   ip route get 1.1.1.1
    #   => dev ens18
    externalInterface = "ens18";

    games = {
      ark = {
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

      rust = {
        key = "rust";
        user = "game-rust";
        uid = 27008;
        gid = 27008;
        home = "/home/game-rust";
        containerName = "neko7-rust";
        hostAddress = "10.77.20.1";
        localAddress = "10.77.20.2";
        tailscaleHostname = "neko7-rust";

        udpPorts = [
          # Rust game / query.
          28015
          28017
        ];

        tcpPorts = [
          # Rust RCON / Rust+.
          # Tailscale policy should expose these to owner/admin only.
          28016
          28082
        ];
      };
    };

    # NOTE: これ伝播するわけじゃないから別途必要
    steamUnfreeNames = [
      "steamcmd"
      "steam"
      "steam-run"
      "steam-original"
      "steam-unwrapped"
    ];
    mkSteamUnfreePolicy = {lib, ...}: {
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) steamUnfreeNames;
    };

    mkHostUser = _name: spec: {
      users.groups.${spec.user}.gid = spec.gid;

      users.users.${spec.user} = {
        isNormalUser = true;
        uid = spec.uid;
        group = spec.user;
        home = spec.home;
        createHome = true;
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        description = "${spec.containerName} service account";
      };
    };

    mkHostTmpfiles = _name: spec: [
      "d ${spec.home} 0750 ${spec.user} ${spec.user} - -"

      # Human-maintained runtime root.
      "d ${spec.home}/${spec.key} 0750 ${spec.user} ${spec.user} - -"
      "d ${spec.home}/${spec.key}/server 0750 ${spec.user} ${spec.user} - -"
      "d ${spec.home}/${spec.key}/backups 0750 ${spec.user} ${spec.user} - -"

      # Root-owned secrets. Game processes should not be able to read auth keys.
      "d ${spec.home}/secrets 0700 root root - -"

      # Tailscale node identity. Persist this, or the container becomes a new node.
      "d ${spec.home}/.state 0750 root root - -"
      "d ${spec.home}/.state/tailscale 0700 root root - -"
    ];

    mkContainerUserModule = spec: {
      lib,
      pkgs,
      ...
    }: {
      users.groups.${spec.user}.gid = spec.gid;

      users.users.${spec.user} = {
        isNormalUser = true;
        uid = spec.uid;
        group = spec.user;
        home = spec.home;
        createHome = true;
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        description = "${spec.containerName} service account";
      };
    };

    mkTailscaleNodeModule = spec: {
      lib,
      pkgs,
      ...
    }: {
      networking.hostName = spec.tailscaleHostname;

      networking.useHostResolvConf = lib.mkForce false;
      networking.nameservers = [
        "1.1.1.1"
        "8.8.8.8"
      ];

      services.tailscale = {
        enable = true;

        # Let NixOS firewall rules on tailscale0 remain meaningful.
        extraSetFlags = [
          "--netfilter-mode=nodivert"
        ];
      };

      systemd.services.tailscale-autoconnect = {
        description = "Authenticate ${spec.tailscaleHostname} to Tailscale";

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

        unitConfig = {
          ConditionPathExists = "${spec.home}/secrets/tailscale-authkey";
        };

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
            echo "${spec.tailscaleHostname} is already authenticated to Tailscale."
            exit 0
          fi

          auth_key="$(tr -d '\r\n' < ${spec.home}/secrets/tailscale-authkey)"

          if [ -z "$auth_key" ]; then
            echo "Empty Tailscale auth key: ${spec.home}/secrets/tailscale-authkey" >&2
            exit 1
          fi

          tailscale up \
            --auth-key "$auth_key" \
            --hostname "${spec.tailscaleHostname}" \
            --accept-dns=false
        '';
      };
      networking.firewall.enable = true;
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = spec.udpPorts;
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = spec.tcpPorts;

      environment.systemPackages = with pkgs; [
        bind
        curl
        jq
        netcat
        tailscale
      ];
    };

    mkBaseContainerModule = spec: args:
      mkMerge [
        {
          system.stateVersion = "26.05";

          systemd.tmpfiles.rules = mkHostTmpfiles spec.key spec;
        }

        (mkSteamUnfreePolicy args)
        (mkContainerUserModule spec args)
        (mkTailscaleNodeModule spec args)
      ];

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

    mkRustModule = spec: {
      lib,
      pkgs,
      ...
    }: let
      home = spec.home;
      installDir = "${home}/rust/server";
      backupDir = "${home}/rust/backups";
      envFile = "${home}/secrets/rust.env";
      serverBinary = "${installDir}/RustDedicated";
    in {
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

        environment = {
          HOME = home;
        };

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
          User = spec.user;
          Group = spec.user;
          WorkingDirectory = home;
          TimeoutStartSec = "45min";
        };
      };
    };

    mkContainer = spec: gameModule: {
      containers.${spec.containerName} = {
        autoStart = false;
        privateNetwork = true;
        enableTun = true;

        hostAddress = spec.hostAddress;
        localAddress = spec.localAddress;

        bindMounts = {
          "${spec.home}" = {
            hostPath = spec.home;
            isReadOnly = false;
          };

          "/var/lib/tailscale" = {
            hostPath = "${spec.home}/.state/tailscale";
            isReadOnly = false;
          };
        };

        config = containerArgs @ {
          lib,
          pkgs,
          ...
        }:
          mkMerge [
            (mkBaseContainerModule spec containerArgs)
            (gameModule spec containerArgs)
          ];
      };
    };
  in {
    config = mkIf config.local.features.game-server-containers.enable (mkMerge (
      [
        {
          assertions = [
            {
              assertion = externalInterface != "";
              message = "game-server-containers: externalInterface must be set.";
            }
          ];

          systemd.tmpfiles.rules = concatLists (mapAttrsToList mkHostTmpfiles games);

          networking.nat = {
            enable = true;
            externalInterface = externalInterface;
            internalInterfaces = [
              "ve-neko7-ark"
              "ve-neko7-rust"
            ];
          };
        }
      ]
      ++ mapAttrsToList mkHostUser games
      ++ [
        (mkContainer games.ark mkArkModule)
        (mkContainer games.rust mkRustModule)
      ]
    ));
  };
}
