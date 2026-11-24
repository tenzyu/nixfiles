{inputs, self, ...}: {
  perSystem = {system, lib, ...}: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
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
