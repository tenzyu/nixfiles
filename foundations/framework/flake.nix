{
  description = "Feature projection framework for NixOS/Home Manager flakes";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    nix-unit.url = "github:nix-community/nix-unit";
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs @ {flake-parts, ...}: let
    frameworkModule = import ./modules/default.nix {
      frameworkRoot = ./.;
    };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [frameworkModule];

      flake = {
        flakeModules.default = frameworkModule;

        lib = {
          features = import ./modules/lib/features.nix {lib = inputs.nixpkgs.lib;};
          modules = import ./modules/lib/modules.nix {lib = inputs.nixpkgs.lib;};
          policies = args: import ./modules/lib/policies.nix ({lib = inputs.nixpkgs.lib;} // args);
        };
      };

      perSystem = {pkgs, ...}: let
        cliSrc = pkgs.lib.cleanSource ./cli;
      in {
        checks.framework-cli =
          pkgs.runCommand "framework-cli-check" {
            src = cliSrc;
            nativeBuildInputs = [
              pkgs.bun
              pkgs.typescript
            ];
          } ''
            set -euo pipefail
            cp -r "$src" ./cli
            chmod -R u+w ./cli
            cd ./cli
            tsc --noEmit
            bun test
            touch "$out"
          '';
      };
    };
}
