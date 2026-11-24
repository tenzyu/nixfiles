{inputs, ...}: let
  nixpkgs = inputs.nixpkgs;
  module = {...}: {
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
    # The peer device IDs, folder membership, GUI password and Tailnet
    # enrollment are operator-owned runtime data, not image inputs.
    networking.firewall.interfaces.tailscale0 = {
      allowedTCPPorts = [22000];
      allowedUDPPorts = [22000];
    };
  };
in {
  perSystem = {system, lib, ...}: lib.mkIf (system == "x86_64-linux") {
    packages = import ./_internal/incus-image.nix {
      inherit nixpkgs system module;
      name = "syncthing";
    };
    checks.personal-workload-syncthing = let
      pkgs = nixpkgs.legacyPackages.${system};
    in pkgs.testers.runNixOSTest {
      name = "personal-workload-syncthing";
      nodes = {
        workload = {
          imports = [module];
          virtualisation.memorySize = 1024;
          virtualisation.cores = 2;
          environment.systemPackages = [pkgs.curl pkgs.jq];
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
        workload.fail("grep -q '<folder ' /var/lib/syncthing/.config/syncthing/config.xml")
        peer.fail("nc -z -w 2 workload 22000")
      '';
    };
  };
}
