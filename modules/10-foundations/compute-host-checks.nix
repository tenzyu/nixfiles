{inputs, self, ...}: {
  perSystem = {system, lib, ...}: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
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
    };
  };
}
