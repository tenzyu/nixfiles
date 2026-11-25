{inputs, self, ...}: {
  perSystem = {system, lib, ...}: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      multi-machine-lab = import ./_internal/multi-machine-lab-test.nix {
        inherit inputs system;
      };
      platform-services = import ./_internal/platform-services-test.nix {
        inherit inputs self system;
      };
      workload-lifecycle = import ./_internal/workload-lifecycle-test.nix {
        inherit inputs system;
      };
      tailnet-ingress = import ./_internal/tailnet-ingress-test.nix {
        inherit inputs self system;
      };
      compute-host-container = import ./_internal/compute-host-test.nix {
        inherit inputs self system;
        vm = false;
      };
      compute-host-vm = import ./_internal/compute-host-test.nix {
        inherit inputs self system;
        vm = true;
      };
      compute-host-vm-tcg = import ./_internal/compute-host-test.nix {
        inherit inputs self system;
        vm = true;
        tcg = true;
      };
    };
  };
}
