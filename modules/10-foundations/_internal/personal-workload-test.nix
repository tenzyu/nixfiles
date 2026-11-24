{inputs, system, workload}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  syncthing = workload == "syncthing";
  port = if syncthing then "8384" else "2283";
  path = if syncthing then "/" else "/api/server/ping";
  unit = if syncthing then "syncthing.service" else "immich-server.service";
in pkgs.testers.runNixOSTest {
  name = "personal-workload-${workload}";
  nodes = {
    workload = {
      imports = [ (if syncthing then ../../40-workloads/_internal/syncthing.nix else ../../40-workloads/_internal/immich.nix) ];
      virtualisation.memorySize = if syncthing then 1024 else 4096;
      virtualisation.cores = 2;
      environment.systemPackages = [pkgs.curl pkgs.jq];
    };
    peer = {environment.systemPackages = [pkgs.curl pkgs.netcat-openbsd];};
  };
  testScript = ''
    start_all()
    workload.wait_for_unit("${unit}")
    workload.wait_until_succeeds("curl -fsS --max-time 5 http://127.0.0.1:${port}${path} >/tmp/response", timeout=180)
    peer.fail("curl -fsS --connect-timeout 2 --max-time 4 http://workload:${port}${path}")
    ${if syncthing then ''
      workload.wait_for_unit("syncthing-init.service")
      workload.succeed("ss -ltn | grep -F '127.0.0.1:8384'")
      workload.succeed("test -d /var/lib/syncthing")
      peer.fail("nc -z -w 2 workload 22000")
    '' else ''
      workload.wait_for_unit("postgresql.service")
      workload.wait_for_unit("redis-immich.service")
      workload.succeed("jq -e '.res == \"pong\"' /tmp/response")
      workload.succeed("test -d /var/lib/immich")
      peer.fail("nc -z -w 2 workload 5432")
      peer.fail("nc -z -w 2 workload 6379")
    ''}
  '';
}
