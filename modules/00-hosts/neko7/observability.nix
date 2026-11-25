{...}: {
  configurations.nixos.neko7.module = {
    # Placement-specific endpoint probes belong to the host composition.
    # No credentials, no application-specific gateway implementation.
    services.prometheus.scrapeConfigs = [{
      job_name = "t3-control-plane";
      metrics_path = "/probe";
      params.module = ["http_ok"];
      static_configs = [{targets = ["http://127.0.0.1:3773/"];}];
      relabel_configs = [
        {source_labels = ["__address__"]; target_label = "__param_target";}
        {source_labels = ["__param_target"]; target_label = "instance";}
        {target_label = "__address__"; replacement = "127.0.0.1:9115";}
      ];
    }];
  };
}
