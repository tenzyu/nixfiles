{inputs, self, ...}: let
  # Stable pins an explicitly insecure/EOL Immich 2.x (CVE-2026-59258).
  # Use the entire isolated guest's existing unstable pin (Immich 3.4.1),
  # not permittedInsecurePackages or a cross-release package injection.
  nixpkgs = inputs.nixpkgs-unstable;
  module = {pkgs, ...}: {
    environment.etc."neko7/readiness".source = pkgs.writeShellScript "immich-ready" ''
      set -euo pipefail
      systemctl is-active --quiet immich-server.service
      ${pkgs.curl}/bin/curl -fsS --max-time 5 http://127.0.0.1:2283/api/server/ping | ${pkgs.jq}/bin/jq -e '.res == "pong"' >/dev/null
    '';
    services.immich = {
      enable = true;
      host = "127.0.0.1";
      port = 2283;
      openFirewall = false;
      mediaLocation = "/var/lib/immich";
      # Baseline CPU-only service; enable ML/GPU in a reviewed guest release
      # after actual resource availability and device parity are verified.
      machine-learning.enable = false;
      accelerationDevices = [];
      database.enable = true;
      redis.enable = true;
    };
  };
in {
  perSystem = {system, lib, ...}: let
    releases = import ./_internal/incus-image.nix {
      inherit nixpkgs system module;
      name = "immich";
    };
    candidate = (import ./_internal/incus-image.nix {
      inherit nixpkgs system module;
      name = "immich";
      extraModules = [{environment.etc."neko7/fixture-release".text = "candidate";}];
    }).neko7-immich-system;
  in lib.mkIf (system == "x86_64-linux") {
    packages = releases;
    checks.incus-workload-immich = import ./_internal/incus-lifecycle.nix {
      inherit inputs self system candidate;
      name = "immich";
      image = releases.neko7-immich-image;
      guestMemory = "3GiB";
      stateProbe = {
        seed = "runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d immich -c 'CREATE TABLE fixture_acceptance (value integer); INSERT INTO fixture_acceptance VALUES (82);'; echo preserved > /var/lib/immich/fixture-data";
        verify = "grep -Fx preserved /var/lib/immich/fixture-data; runuser -u postgres -- psql -At -d immich -c 'SELECT value FROM fixture_acceptance' | grep -Fx 82";
      };
    };
    checks.personal-workload-immich = let
      pkgs = nixpkgs.legacyPackages.${system};
    in pkgs.testers.runNixOSTest {
      name = "personal-workload-immich";
      nodes = {
        workload = {
          imports = [module];
          virtualisation.memorySize = 4096;
          virtualisation.cores = 2;
          environment.systemPackages = [pkgs.curl pkgs.jq];
        };
        peer.environment.systemPackages = [pkgs.curl pkgs.netcat-openbsd];
      };
      testScript = ''
        start_all()
        workload.wait_for_unit("immich-server.service")
        workload.wait_until_succeeds("curl -fsS --max-time 5 http://127.0.0.1:2283/api/server/ping >/tmp/response", timeout=180)
        peer.fail("curl -fsS --connect-timeout 2 --max-time 4 http://workload:2283/api/server/ping")
        workload.wait_for_unit("postgresql.service")
        workload.wait_for_unit("redis-immich.service")
        workload.succeed("jq -e '.res == \"pong\"' /tmp/response")
        workload.succeed("test -d /var/lib/immich")
        peer.fail("nc -z -w 2 workload 5432")
        peer.fail("nc -z -w 2 workload 6379")
      '';
    };
  };
}
