{
  config,
  lib,
  inputs,
  ...
}: {
  imports = [inputs.flake-parts.flakeModules.modules];

  config = {
    _module.args = {
      nixos = config.flake.modules.nixos;
      homeManager = config.flake.modules.homeManager;
      cross = config.flake.lib.cross;
    };

    flake.modules = lib.mkDefault {
      homeManager = {};
      nixos = {};
    };
  };
}
