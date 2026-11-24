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
    checks.personal-workload-syncthing = import ../10-foundations/_internal/personal-workload-test.nix {
      inherit nixpkgs system module;
      workload = "syncthing";
    };
  };
}
