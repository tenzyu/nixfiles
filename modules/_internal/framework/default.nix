{...}: {
  # import-tree skips _internal; this bridge is explicitly imported by flake.nix.
  imports = [
    ./flake-modules.nix
    ./configurations.nix
  ];
}
