{inputs, ...}: {
  perSystem = {system, lib, ...}: {
    checks = lib.optionalAttrs (inputs.splitcast.checks ? ${system}) {
      splitcast-configs = inputs.splitcast.checks.${system}.configs;
    };
  };
}
