{inputs, ...}: let
  # Stable pins an explicitly insecure/EOL Immich 2.x (CVE-2026-59258).
  # Use the entire isolated guest's existing unstable pin (Immich 3.4.1),
  # not permittedInsecurePackages or a cross-release package injection.
  nixpkgs = inputs.nixpkgs-unstable;
  module = {...}: {
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
  perSystem = {system, lib, ...}: lib.mkIf (system == "x86_64-linux") {
    packages = import ./_internal/incus-image.nix {
      inherit nixpkgs system module;
      name = "immich";
    };
    checks.personal-workload-immich = import ../10-foundations/_internal/personal-workload-test.nix {
      inherit nixpkgs system module;
      workload = "immich";
    };
  };
}
