{...}: {
  flake.modules.nixos.remote-execution-mcp-network = {config, lib, ...}: let
    cfg = config.local.remoteExecutionMcp;
    bridge = "incusmcp0";
    uplink = config.networking.nat.externalInterface;
    cidr = lib.types.strMatching "[0-9.]+/[0-9]+";
    gateway = builtins.head (lib.splitString "/" cfg.bridgeAddress);
    blocked = [
      "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10" "127.0.0.0/8"
      "169.254.0.0/16" "172.16.0.0/12" "192.168.0.0/16"
      "198.18.0.0/15" "224.0.0.0/4" "240.0.0.0/4"
    ] ++ cfg.protectedIPv4;
  in {
    options.local.remoteExecutionMcp = {
      bridgeAddress = lib.mkOption {
        type = cidr;
        example = "10.77.42.1/24";
        description = "Operator-selected nonoverlapping Incus bridge address.";
      };
      protectedIPv4 = lib.mkOption {
        type = lib.types.listOf cidr;
        default = [];
        description = "Additional protected routed prefixes, including any globally numbered LAN.";
      };
    };
    config = lib.mkIf config.local.features.remote-execution-mcp-network.enable {
      assertions = [
        {
          assertion = config.virtualisation.incus.enable;
          message = "Remote Execution MCP requires the existing Incus substrate.";
        }
        {
          assertion = config.networking.nftables.enable && config.networking.firewall.enable;
          message = "Remote Execution MCP requires nftables and the host firewall.";
        }
        {
          assertion = uplink != null && uplink != "" && uplink != bridge && uplink != "lo";
          message = "Remote Execution MCP requires an explicit physical NAT uplink.";
        }
      ];
      users.groups.remote-mcp-tunnel = {};
      users.users.remote-mcp-tunnel = {
        isSystemUser = true;
        group = "remote-mcp-tunnel";
      };
      virtualisation.incus.preseed = {
        networks = lib.mkAfter [{
          name = bridge;
          type = "bridge";
          config = {
            "ipv4.address" = cfg.bridgeAddress;
            "ipv4.nat" = "true";
            "ipv6.address" = "none";
          };
        }];
        profiles = lib.mkAfter [{
          name = "remote-execution-mcp";
          project = "default";
          config = {
            "security.privileged" = "false";
            "security.idmap.isolated" = "true";
            "security.nesting" = "false";
          };
          devices = {
            root = {type = "disk"; pool = "default"; path = "/";};
            eth0 = {type = "nic"; name = "eth0"; network = bridge;};
          };
        }];
      };
      networking.firewall.interfaces.${bridge} = {
        allowedTCPPorts = [53];
        allowedUDPPorts = [53 67];
      };
      # Syntax check runs outside the activated user database. Runtime test
      # uses the real service UID and denies a different ordinary user.
      networking.nftables.preCheckRuleset = ''
        sed -i 's/"remote-mcp-tunnel"/65534/g' ruleset.conf
      '';
      networking.nftables.tables.remote_execution_mcp = {
        family = "inet";
        content = ''
          chain input {
            type filter hook input priority -10; policy accept;
            iifname "${bridge}" meta nfproto ipv6 drop
            iifname "${bridge}" ct state { established, related } accept
            iifname "${bridge}" ip daddr { ${gateway}, 255.255.255.255 } udp sport 68 udp dport 67 accept
            iifname "${bridge}" ip daddr ${gateway} udp dport 53 accept
            iifname "${bridge}" ip daddr ${gateway} tcp dport 53 accept
            iifname "${bridge}" drop
          }
          chain forward {
            type filter hook forward priority -10; policy accept;
            iifname "${bridge}" meta nfproto ipv6 drop
            oifname "${bridge}" meta nfproto ipv6 drop
            iifname "${bridge}" ip daddr { ${lib.concatStringsSep ", " blocked} } drop
            iifname "${bridge}" oifname ${builtins.toJSON (if uplink == null then "" else uplink)} ct state { new, established, related } accept
            iifname "${bridge}" drop
            oifname "${bridge}" iifname ${builtins.toJSON (if uplink == null then "" else uplink)} ct state { established, related } accept
            oifname "${bridge}" drop
          }
          chain output {
            type filter hook output priority -10; policy accept;
            oifname "${bridge}" meta nfproto ipv6 drop
            oifname "${bridge}" ct state { established, related } accept
            oifname "${bridge}" udp sport 67 udp dport 68 accept
            oifname "${bridge}" tcp dport 18991 meta skuid { 0, "remote-mcp-tunnel" } accept
            oifname "${bridge}" drop
          }
        '';
      };
    };
  };
}
