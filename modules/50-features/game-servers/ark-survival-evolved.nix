{
  flake.local.featurePolicies.ark-survival-evolved.unfree = [
    "steamcmd"
    "steam"
    "steam-run"
    "steam-original"
    "steam-unwrapped"
  ];

  flake.modules.nixos.ark-survival-evolved = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.ark-survival-evolved.enable {
      # rcon webui {{{
      virtualisation.oci-containers.backend = "docker";

      virtualisation.oci-containers.containers.ark-rcon-web-admin = {
        image = "itzg/rcon:latest";
        autoStart = true;

        # Host network にすると、container から ARK RCON を 127.0.0.1:27020 で叩ける。
        extraOptions = [
          "--network=host"
          "--env-file=/var/lib/ark/rcon-web-admin.env"
        ];

        volumes = [
          "/var/lib/ark/rcon-web-admin:/opt/rcon-web-admin/db"
        ];

        environment = {
          RWA_ENV = "TRUE";
          RWA_USERNAME = "admin";
          RWA_ADMIN = "TRUE";

          RWA_GAME = "other";
          RWA_SERVER_NAME = "neko7-ark";

          RWA_RCON_HOST = "127.0.0.1";
          RWA_RCON_PORT = "27020";
        };
      };

      # Browser UI only.
      # 27020 は Web UI が localhost から叩くので、Tailscale に開けなくてもよい。
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        4326
        4327
      ];
      # }}}
      # server {{{
      users.groups.ark = {};

      users.users.ark = {
        isSystemUser = true;
        group = "ark";
        home = "/var/lib/ark";
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/ark 0750 ark ark - -"
        "d /var/lib/ark/server 0750 ark ark - -"
        "d /var/lib/ark/backups 0750 ark ark - -"
      ];

      networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
        7777
        7778
        27015
      ];

      systemd.services.ark-survival-evolved = {
        description = "ARK: Survival Evolved Dedicated Server";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target" "tailscaled.service"];
        after = ["network-online.target" "tailscaled.service"];

        path = with pkgs; [
          coreutils
          findutils
          gnutar
          gzip
          steamcmd
          steam-run
        ];

        environment = {
          HOME = "/var/lib/ark";
        };

        preStart = ''
          set -euo pipefail

          install -d -m 0750 /var/lib/ark/server /var/lib/ark/backups

          if [ -d /var/lib/ark/server/ShooterGame/Saved ]; then
            backup="/var/lib/ark/backups/saved-$(date +%Y%m%d-%H%M%S).tar.gz"
            tar -C /var/lib/ark/server/ShooterGame -czf "$backup" Saved
            find /var/lib/ark/backups -type f -name 'saved-*.tar.gz' -mtime +14 -delete
          fi

          steamcmd \
            +force_install_dir /var/lib/ark/server \
            +login anonymous \
            +app_update 376030 validate \
            +quit
        '';

        script = ''
          set -euo pipefail

          : "''${ARK_MAP:=TheIsland}"
          : "''${ARK_SESSION_NAME:=neko7-ark}"
          : "''${ARK_SERVER_PASSWORD:=}"
          : "''${ARK_ADMIN_PASSWORD:?Set ARK_ADMIN_PASSWORD in /var/lib/ark/ark-survival-evolved.env}"
          : "''${ARK_GAME_PORT:=7777}"
          : "''${ARK_QUERY_PORT:=27015}"
          : "''${ARK_MAX_PLAYERS:=10}"
          : "''${ARK_EXTRA_URL_OPTIONS:=}"
          : "''${ARK_EXTRA_ARGS:=}"

          cd /var/lib/ark/server/ShooterGame/Binaries/Linux

          url="''${ARK_MAP}?listen?SessionName=''${ARK_SESSION_NAME}?ServerPassword=''${ARK_SERVER_PASSWORD}?ServerAdminPassword=''${ARK_ADMIN_PASSWORD}?Port=''${ARK_GAME_PORT}?QueryPort=''${ARK_QUERY_PORT}?MaxPlayers=''${ARK_MAX_PLAYERS}''${ARK_EXTRA_URL_OPTIONS}"

          exec steam-run ./ShooterGameServer "$url" -server -log ''${ARK_EXTRA_ARGS}
        '';

        serviceConfig = {
          User = "ark";
          Group = "ark";
          StateDirectory = "ark";
          WorkingDirectory = "/var/lib/ark";
          EnvironmentFile = "/var/lib/ark/ark-survival-evolved.env";

          Restart = "on-failure";
          RestartSec = "10s";

          TimeoutStartSec = "45min";
          TimeoutStopSec = "120s";
          KillSignal = "SIGINT";

          LimitNOFILE = 1048576;
        };
      };
      # }}}
    };
  };
}
