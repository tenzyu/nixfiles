{moduleWithSystem, ...}: {
  local.cross.definitions.antigravity.home.module = moduleWithSystem ({inputs', ...}: {
    home.packages = [
      inputs'.antigravity-nix.packages.default
    ];
  });
}
