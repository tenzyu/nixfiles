{inputs, ...}: {
  perSystem = {system, lib, ...}: {
    packages = lib.optionalAttrs (inputs.splitcast.packages ? ${system})
      (lib.filterAttrs (name: _: name != "default") inputs.splitcast.packages.${system});
  };
}
