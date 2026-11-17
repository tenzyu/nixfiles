{lib}: let
  modulesLib = import ../lib/modules.nix {inherit lib;};
in {
  testPublicModuleAttrsDropsPrivate = {
    expr = modulesLib.publicModuleAttrs {
      _private = {x = 1;};
      public = {y = 2;};
      _alsoPrivate = {z = 3;};
    };
    expected = {
      public = {y = 2;};
    };
  };

  testTagNixosModuleAddsFileAndImports = {
    expr = modulesLib.tagNixosModule "alpha" {config.foo = "bar";};
    expected = {
      _file = "flake.modules.nixos.alpha";
      imports = [{config.foo = "bar";}];
    };
  };

  testTagHomeModuleAddsFileAndImports = {
    expr = modulesLib.tagHomeModule "beta" {config.foo = "baz";};
    expected = {
      _file = "flake.modules.homeManager.beta";
      imports = [{config.foo = "baz";}];
    };
  };
}
