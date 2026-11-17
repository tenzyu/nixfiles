{lib, ...}: {
  options.flake.local.featurePolicies = lib.mkOption {
    default = {};
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        unfree = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };

        permittedInsecure = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
      };
    });
    description = ''
      Per-feature package admissibility policy declarations. Each feature
      module may declare its required unfree and permittedInsecure package
      names here; the framework materializer collects the active feature
      set's policy into `local.nixpkgsPolicy`.
    '';
  };
}
