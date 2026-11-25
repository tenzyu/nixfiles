{inputs, ...}: let
  nixpkgs = inputs.nixpkgs;
  module = {pkgs, ...}: {
    services.syncthing = {
      enable = true;
      dataDir = "/var/lib/syncthing";
      guiAddress = "127.0.0.1:8384";
      openDefaultPorts = false;
      overrideDevices = false;
      overrideFolders = false;
      settings.options = {
        globalAnnounceEnabled = false;
        localAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        listenAddresses = ["tcp://0.0.0.0:22000" "quic://0.0.0.0:22000"];
      };
    };
    environment.etc."neko7/readiness".source = pkgs.writeShellScript "syncthing-ready" ''
      set -euo pipefail
      # Incus VM agent exec is not a login shell: do not depend on PATH.
      ${pkgs.systemd}/bin/systemctl is-active --quiet syncthing.service
      ${pkgs.curl}/bin/curl -fsS --max-time 5 http://127.0.0.1:8384/ >/dev/null
    '';
    # The peer device IDs, folder membership, GUI password and Tailnet
    # enrollment are operator-owned runtime data, not image inputs.
    networking.firewall.interfaces.tailscale0 = {
      allowedTCPPorts = [22000];
      allowedUDPPorts = [22000];
    };
  };
in {
  perSystem = {system, lib, ...}: let
    releases = import ./_internal/incus-image.nix {
      inherit nixpkgs system module;
      name = "syncthing";
    };
  in lib.mkIf (system == "x86_64-linux") {
    packages = releases;
    checks.personal-workload-syncthing = let
      pkgs = nixpkgs.legacyPackages.${system};
    in pkgs.testers.runNixOSTest {
      name = "personal-workload-syncthing";
      nodes = {
        workload = {
          imports = [module];
          virtualisation.memorySize = 1024;
          virtualisation.cores = 2;
          environment.systemPackages = [pkgs.curl pkgs.jq pkgs.python3];
        };
        peer.environment.systemPackages = [pkgs.curl pkgs.netcat-openbsd];
      };
      testScript = ''
        start_all()
        workload.wait_for_unit("syncthing.service")
        workload.wait_until_succeeds("curl -fsS --max-time 5 http://127.0.0.1:8384/ >/tmp/response", timeout=180)
        peer.fail("curl -fsS --connect-timeout 2 --max-time 4 http://workload:8384/")
        workload.wait_for_unit("syncthing-init.service")
        workload.succeed("ss -ltn | grep -F '127.0.0.1:8384'")
        workload.succeed("test -d /var/lib/syncthing && test -s /var/lib/syncthing/.config/syncthing/config.xml")
        # Defaults templates are not actual replication folders.
        workload.succeed("python3 -c 'import xml.etree.ElementTree as E; r=E.parse(\"/var/lib/syncthing/.config/syncthing/config.xml\").getroot(); print(\"folders\", [f.attrib for f in r.findall(\"./folder\")]); print(\"defaults\", len(r.findall(\"./defaults/folder\"))); assert not r.findall(\"./folder\"); assert len(r.findall(\"./device\")) <= 1; o=r.find(\"options\"); assert all(o.findtext(k)==\"false\" for k in [\"globalAnnounceEnabled\",\"localAnnounceEnabled\",\"relaysEnabled\",\"natEnabled\"])'")
        workload.succeed("env -i PATH=/nonexistent /etc/neko7/readiness")
        peer.fail("nc -z -w 2 workload 22000")
      '';
    };
  };
}
