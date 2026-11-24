{...}: {
  flake.modules.nixos.platform-observability = {
    config,
    lib,
    pkgs,
    ...
  }: let
    incus = config.local.features.incus.enable or false;
    gpu = config.local.features.nvidia-graphics.enable or false;
    preview = config.local.features.preview-gateway.enable or false;
    dashboard = import ./_internal/platform-dashboard.nix {inherit pkgs;};
    scrape = name: address: {
      job_name = name;
      static_configs = [{targets = [address];}];
    };
    probe = name: module: target: {
      job_name = name;
      metrics_path = "/probe";
      params.module = [module];
      static_configs = [{targets = [target];}];
      relabel_configs = [
        {source_labels = ["__address__"]; target_label = "__param_target";}
        {source_labels = ["__param_target"]; target_label = "instance";}
        {target_label = "__address__"; replacement = "127.0.0.1:9115";}
      ];
    };
  in {
    config = lib.mkIf config.local.features.platform-observability.enable {
      services.prometheus = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9090;
        retentionTime = "7d";
        extraFlags = ["--storage.tsdb.retention.size=2GB"];
        globalConfig.scrape_interval = "30s";
        exporters = {
          node = {
            enable = true;
            listenAddress = "127.0.0.1";
            openFirewall = false;
            enabledCollectors = ["systemd"];
          };
          blackbox = {
            enable = true;
            listenAddress = "127.0.0.1";
            openFirewall = false;
            configFile = pkgs.writeText "blackbox.json" (builtins.toJSON {
              modules = {
                http_ok = {prober = "http"; timeout = "5s"; http.preferred_ip_protocol = "ip4";};
                tcp_connect = {prober = "tcp"; timeout = "5s";};
              };
            });
          };
          nvidia-gpu = lib.mkIf gpu {
            enable = true;
            listenAddress = "127.0.0.1";
            openFirewall = false;
          };
        };
        scrapeConfigs =
          [
            (scrape "host" "127.0.0.1:9100")
            (scrape "prometheus" "127.0.0.1:9090")
          ]
          ++ lib.optional gpu (scrape "gpu" "127.0.0.1:9835")
          ++ lib.optional preview (probe "preview-gateway" "tcp_connect" "127.0.0.1:18080")
          ++ lib.optional incus {
            job_name = "incus";
            scheme = "https";
            metrics_path = "/1.0/metrics";
            # Separate loopback-only read-only metrics listener, NOT the API.
            # Self-signed metrics transport is local; do not generalize this
            # skip-verification setting to remote scrape targets.
            tls_config.insecure_skip_verify = true;
            static_configs = [{targets = ["127.0.0.1:8444"];}];
          };
      };
      virtualisation.incus.preseed.config = lib.mkIf incus {
        "core.metrics_address" = "127.0.0.1:8444";
        "core.metrics_authentication" = "false";
      };
      services.grafana = {
        enable = true;
        openFirewall = false;
        settings = {
          server = {http_addr = "127.0.0.1"; http_port = 13000;};
          # Read-only local operator dashboard behind the existing SSH
          # boundary. No default admin password or externally trusted header.
          security.disable_initial_admin_creation = true;
          "auth.anonymous" = {enabled = true; org_role = "Viewer";};
          auth.disable_login_form = true;
          analytics.reporting_enabled = false;
          analytics.check_for_updates = false;
          analytics.check_for_plugin_updates = false;
          users.allow_sign_up = false;
        };
        provision = {
          enable = true;
          datasources.settings.datasources = [{
            name = "Platform";
            uid = "platform-prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:9090";
            isDefault = true;
            editable = false;
          }];
          dashboards.settings.providers = [{
            name = "platform";
            disableDeletion = true;
            allowUiUpdates = false;
            options.path = dashboard;
          }];
        };
      };
    };
  };
}
