{
  perSystem = {inputs', ...}: {
    formatter = inputs'.nixpkgs.legacyPackages.alejandra;
  };
}
