# Opt-in security boundary for a stock OBS WebSocket listener on neko7.
# This module is intentionally NOT enabled by either host.
# Enabling nftables can change the system firewall backend; inspect the
# effective ruleset and complete the remote reachability checks first.
{
  flake.modules.nixos.splitcast-stock-obs-firewall = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.splitcast-stock-obs-firewall.enable {
      networking.nftables = {
        enable = true;
        tables."splitcast-obs-websocket-guard" = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority -150; policy accept;
              # Block IPv4 and IPv6 inbound WebSocket TCP, even from tailscale0.
              # OBS itself may listen on wildcard addresses: do not trust bind state.
              iifname != "lo" tcp dport 4455 counter drop
            }
          '';
        };
      };
    };
  };
}
