{inputs, ...}: {
  local.cross.definitions.antigravity.home.packages = pkgs: [
    inputs.antigravity-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
