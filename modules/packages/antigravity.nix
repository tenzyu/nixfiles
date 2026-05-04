{
  cross,
  inputs,
  ...
}:
cross.module {
  name = "antigravity";

  home.packages = pkgs: [
    inputs.antigravity-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
