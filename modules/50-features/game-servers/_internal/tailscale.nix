{lib, pkgs}: let
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

in mkTailscaleNodeModule
