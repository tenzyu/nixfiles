{
  config,
  cross,
  lib,
  ...
}: {
  options.local.cross.modules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = {};
    description = "Collected cross modules for NixOS + Home Manager user boundaries.";
  };

  config.flake.lib.cross =
    cross
    // {
      modules = config.local.cross.modules;
    };
}
