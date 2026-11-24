{...}: {
  flake.modules.nixos.preview-gateway = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = pkgs.writeText "preview-gateway.json" (builtins.toJSON {
      admin = {
        listen = "unix//run/neko7-preview/admin.sock|0600";
        config.persist = false;
      };
      apps.http.servers.preview = {
        listen = ["127.0.0.1:18080"];
        automatic_https.disable = true;
        routes = [
          {
            "@id" = "preview-default";
            handle = [{
              handler = "static_response";
              status_code = 404;
              body = "No approved preview at this path";
            }];
          }
        ];
      };
    });
  in {
    config = lib.mkIf config.local.features.preview-gateway.enable {
      # Native Caddy API owns ephemeral routes. No application registry,
      # no wildcard listener, no delegated daemon admin or public tunnel.
      systemd.services.preview-gateway = {
        description = "Private ephemeral HTTP preview gateway";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.caddy} run --config ${cfg}";
          DynamicUser = true;
          RuntimeDirectory = "neko7-preview";
          RuntimeDirectoryMode = "0700";
          StateDirectory = "neko7-preview";
          Environment = ["XDG_DATA_HOME=/var/lib/neko7-preview" "XDG_CONFIG_HOME=/var/lib/neko7-preview"];
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
          CapabilityBoundingSet = "";
          # Bound the proxy's IP reach to the local listener and Incus
          # private bridges. This is not an agent-facing admin API.
          IPAddressDeny = "any";
          IPAddressAllow = ["localhost" "10.77.41.0/24"];
          SocketBindDeny = "any";
          SocketBindAllow = ["ipv4:tcp:18080"];
          Restart = "on-failure";
        };
      };
    };
  };
}
