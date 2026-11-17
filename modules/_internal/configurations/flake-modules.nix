{
  inputs,
  lib,
  ...
}: {
  imports = [inputs.flake-parts.flakeModules.modules];

  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = {};
    description = ''
      Framework helper surface exposed to host modules via `_module.args`
      (e.g. `helpers`).
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
