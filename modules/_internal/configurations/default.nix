{
  inputs,
  lib,
  ...
}: {
  # import-tree skips _internal, so flake.nix imports this entry point.
  imports = [
    inputs.flake-parts.flakeModules.modules
    ./configurations.nix
  ];

  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = {};
    description = ''
      Shared helper values and overlays consumed by the configuration adapter.
    '';
  };

  config = {
    # NOTE: Expose flake-parts option declarations for nixd via .#debug.options.
    #       Required for completion inside configurations.nixos.<host>.module, which belongs to the flake-parts option universe.
    debug = true;

    flake.modules = {
      homeManager = {};
      nixos = {};
    };
  };
}
