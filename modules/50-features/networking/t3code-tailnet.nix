{...}: {
  flake.modules.nixos.t3code-tailnet = {
    config,
    lib,
    pkgs,
    ...
  }: let
    port = "8445";
    proxy = "http://127.0.0.1:3773";
  in {
    config = lib.mkIf config.local.features.t3code-tailnet.enable {
      # Serve persists its own state. Run only for an approved route restore.
      systemd.services.t3code-tailnet = {
        description = "Restore the T3 Code tailnet HTTPS route";
        requisite = ["tailscaled.service"];
        after = ["tailscaled.service"];
        path = [config.services.tailscale.package pkgs.jq];
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          host=$(tailscale status --json | jq -er '.Self.DNSName | select(type == "string" and length > 1) | rtrimstr(".")')
          state=$(tailscale serve status --json)
          route=$(jq -er --arg port '${port}' --arg hp "$host:${port}" --arg proxy '${proxy}' '
            def at_port: to_entries[] | select(.key | endswith(":" + $port));
            def occupied:
              .TCP[$port] != null or any(.Web // {} | at_port; true) or
              any(.AllowFunnel // {} | at_port; .value);
            if any(.Foreground[]?; occupied) then "conflict"
            elif (occupied | not) then "absent"
            elif .TCP[$port] == {"HTTPS": true}
              and ([.Web // {} | at_port] == [{"key": $hp, "value": {"Handlers": {"/": {"Proxy": $proxy}}}}])
              and (any(.AllowFunnel // {} | at_port; .value) | not)
            then "present" else "conflict" end
          ' <<< "$state")
          case "$route" in
            present) echo "T3 HTTPS route already matches" ;;
            absent) exec tailscale serve --bg --https=${port} ${proxy} ;;
            *) echo "T3 HTTPS port ${port} is occupied by different Serve state" >&2; exit 1 ;;
          esac
        '';
      };
    };
  };
}
