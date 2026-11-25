{inputs, self, system}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  route = pkgs.writeText "fixture-preview.json" (builtins.toJSON {
    "@id" = "fixture";
    match = [{path = ["/p/fixture/*"];}];
    handle = [
      {handler = "rewrite"; strip_path_prefix = "/p/fixture";}
      {handler = "reverse_proxy"; upstreams = [{dial = "10.77.41.2:8080";}];}
    ];
  });
in pkgs.testers.runNixOSTest {
  name = "platform-services";
  nodes.machine = {lib, ...}: {
    imports = [
      self.modules.nixos.preview-gateway
      self.modules.nixos.platform-observability
      self.modules.nixos.execution-discovery
    ];
    options.local.features = lib.genAttrs ["preview-gateway" "platform-observability" "execution-discovery" "incus" "nvidia-graphics"] (_: {
      enable = lib.mkEnableOption "fixture feature";
    });
    config = {
      local.features = {
        preview-gateway.enable = true;
        platform-observability.enable = true;
        execution-discovery.enable = true;
      };
      virtualisation.memorySize = 2048;
      environment.systemPackages = [pkgs.curl pkgs.jq pkgs.iproute2];
      users.users.observer = {isNormalUser = true;};
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("preview-gateway.service")
    machine.wait_for_unit("prometheus.service")
    machine.wait_for_unit("grafana.service")
    machine.succeed("grep -F 'incus launch' /etc/neko7/execution.md")
    machine.succeed("ip addr add 10.77.41.2/32 dev lo")
    machine.succeed("mkdir -p /tmp/fixture; echo fixture-preview > /tmp/fixture/index.html")
    machine.succeed("systemd-run --unit=preview-fixture ${pkgs.python3}/bin/python3 -m http.server 8080 --bind 10.77.41.2 --directory /tmp/fixture")
    machine.wait_until_succeeds("curl -fsS http://10.77.41.2:8080/ | grep -Fx fixture-preview")
    machine.fail("curl -fsS http://127.0.0.1:18080/p/fixture/")
    api = "curl -fsS --unix-socket /run/neko7-preview/admin.sock http://localhost"
    machine.fail("su - observer -c 'test -w /run/neko7-preview/admin.sock'")
    machine.succeed(api + "/config/ >/dev/null")
    machine.succeed(api + "/config/apps/http/servers/preview/routes/0 -X PUT -H 'Content-Type: application/json' --data-binary @${route}")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:18080/p/fixture/ | grep -Fx fixture-preview")
    machine.succeed(api + "/id/fixture -X DELETE")
    machine.fail("curl -fsS http://127.0.0.1:18080/p/fixture/")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:9090/api/v1/query?query=up | jq -e '.data.result | any(.metric.job == \"host\" and .value[1] == \"1\")'")
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:13000/api/dashboards/uid/neko7-platform | jq -e '.dashboard.uid == \"neko7-platform\"'")
    machine.succeed("ss -ltn | grep -F '127.0.0.1:13000'")
    machine.succeed("ss -ltn | grep -F '127.0.0.1:18080'")
  '';
}
