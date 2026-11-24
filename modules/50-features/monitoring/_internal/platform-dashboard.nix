{pkgs}: let
  datasource = {type = "prometheus"; uid = "platform-prometheus";};
  panel = id: title: expr: unit: {
    inherit id title datasource;
    type = "timeseries";
    gridPos = {h = 8; w = 12; x = if id - 2 * (builtins.div id 2) == 1 then 0 else 12; y = 8 * (builtins.div (id - 1) 2);};
    targets = [{inherit expr datasource; refId = "A"; legendFormat = "{{name}} {{instance}} {{device}} {{mode}}";}];
    fieldConfig.defaults = {inherit unit;};
  };
  # The inventory comes from Incus's exporter labels and the native
  # systemd collector. Do not maintain a second workload database.
  dashboard = {
    uid = "neko7-platform";
    title = "neko7 / Compute platform";
    schemaVersion = 39;
    version = 1;
    refresh = "30s";
    time = {from = "now-1h"; to = "now";};
    links = [
      {title = "Incus UI (SSH forwarded)"; type = "link"; url = "https://localhost:8443/ui/"; targetBlank = true;}
      {title = "Prometheus targets (SSH forwarded)"; type = "link"; url = "http://localhost:9090/targets"; targetBlank = true;}
      {title = "Preview gateway (SSH forwarded)"; type = "link"; url = "http://localhost:18080/"; targetBlank = true;}
      {title = "T3 Code (SSH forwarded)"; type = "link"; url = "http://localhost:3773/"; targetBlank = true;}
    ];
    panels = [
      (panel 1 "Host CPU busy" "100 * (1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])))" "percent")
      (panel 2 "Host available memory" "node_memory_MemAvailable_bytes" "bytes")
      (panel 3 "CPU / I/O / memory pressure" "rate({__name__=~\"node_pressure_(cpu|io|memory)_waiting_seconds_total\"}[5m])" "percentunit")
      (panel 4 "Disk read / write throughput" "rate(node_disk_read_bytes_total[5m]) + rate(node_disk_written_bytes_total[5m])" "Bps")
      (panel 5 "Filesystem available" "node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay\"}" "bytes")
      (panel 6 "Network receive / send throughput" "rate(node_network_receive_bytes_total[5m]) + rate(node_network_transmit_bytes_total[5m])" "Bps")
      (panel 7 "Incus instance CPU (project/name)" "sum by(project,name,type)(rate(incus_cpu_seconds_total{mode!=\"idle\"}[5m]))" "short")
      (panel 8 "Incus memory available (when reported)" "incus_memory_MemAvailable_bytes" "bytes")
      (panel 9 "Exporter reachability" "up" "short")
      (panel 10 "Service endpoint probes" "probe_success" "short")
      (panel 11 "Failed systemd units" "node_systemd_unit_state{state=\"failed\"} == 1" "short")
      (panel 12 "GPU utilization (when available)" "nvidia_smi_utilization_gpu_ratio" "percentunit")
    ];
  };
in pkgs.runCommand "platform-dashboard" {} ''
  mkdir -p "$out"
  cp ${pkgs.writeText "platform.json" (builtins.toJSON dashboard)} "$out/platform.json"
''
