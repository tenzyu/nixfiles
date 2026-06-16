{lib}: rec {
  publicModuleAttrs = attrs:
    lib.filterAttrs (name: _value: !(lib.hasPrefix "_" name)) attrs;

  tagNixosModule = name: module: {
    _file = "flake.modules.nixos.${name}";
    imports = [module];
  };

  tagHomeModule = name: module: {
    _file = "flake.modules.homeManager.${name}";
    imports = [module];
  };
}
