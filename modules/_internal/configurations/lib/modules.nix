{lib}: {
  publicModuleAttrs = attrs:
    lib.filterAttrs (name: _value: !(lib.hasPrefix "_" name)) attrs;

  tagModule = moduleClass: name: module: {
    _file = "flake.modules.${moduleClass}.${name}";
    imports = [module];
  };
}
