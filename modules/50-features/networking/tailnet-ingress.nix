{
  flake.modules.nixos.tailnet-ingress = {
    config,
    lib,
    ...
  }: let
    uplink = config.networking.nat.externalInterface;
    iface = builtins.toJSON (if uplink == null then "" else uplink);
    transport = config.services.tailscale.port;
  in {
    config = lib.mkIf config.local.features.tailnet-ingress.enable {
      networking.nftables.enable = true;
      assertions = [
        {
          assertion = uplink != null && uplink != "" && uplink != "lo" && uplink != config.services.tailscale.interfaceName;
          message = "Tailnet-only ingress requires an explicit non-Tailnet NAT uplink.";
        }
        {
          assertion = config.networking.firewall.enable && config.networking.firewall.backend == "nftables";
          message = "Tailnet-only ingress requires the native nftables firewall.";
        }
        {
          assertion = config.networking.nat.forwardPorts == [] && config.networking.nat.dmzHost == null;
          message = "Tailnet-only ingress prohibits uplink DNAT and DMZ hosts.";
        }
      ];

      # A separate base chain is intentional: an accept in another table
      # (including Incus/Docker/Tailscale) cannot override our drop verdict.
      # Do not flush third-party tables or change the existing outbound policy.
      networking.nftables.tables.tailnet_ingress = {
        family = "inet";
        content = ''
          counter input_denied {}
          counter forward_denied {}
          chain input {
            type filter hook input priority -10; policy accept;
            iifname ${iface} ct state { established, related } accept
            iifname ${iface} udp sport 67 udp dport 68 accept comment "DHCPv4 client"
            iifname ${iface} udp sport 547 udp dport 546 accept comment "DHCPv6 client"
            ${lib.optionalString (config.services.tailscale.enable && transport != 0) ''
              iifname ${iface} udp dport ${toString transport} accept comment "existing encrypted Tailscale transport; not an opening"
            ''}
            iifname ${iface} meta l4proto { tcp, udp } counter name input_denied drop
          }
          chain forward {
            type filter hook forward priority -10; policy accept;
            iifname ${iface} ct state { established, related } accept
            # Includes packets translated by prerouting DNAT, regardless of
            # destination bridge or runtime. Tailnet ingress is unaffected.
            iifname ${iface} counter name forward_denied drop
          }
        '';
      };
    };
  };
}
