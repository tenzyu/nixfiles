{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    package = pkgs.callPackage ../../packages/splitcast-measurement {};
  in {
    packages.splitcast-measurement = package;
    apps.splitcast-measurement = {
      type = "app";
      program = "${package}/bin/splitcast-measurement";
      meta.description = "Run SplitCast measurement tools without starting SplitCast";
    };
  };
}
