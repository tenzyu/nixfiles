{
  inputs,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    nixUnit = inputs.nix-unit.packages.${system}.default;

    # cli-apps.nix is framework/modules/10-framework/cli-apps.nix
    frameworkModuleRoot = ./.;
    frameworkRoot = ../..;
    cliRoot = ../../cli;

    frameworkTestSuite = pkgs.writeText "framework-tests.nix" ''
      let
        lib = import ${inputs.nixpkgs}/lib;
        root = ${frameworkModuleRoot};
      in {
        framework-features = import (root + "/tests/features.nix") { inherit lib; };
        framework-users = import (root + "/tests/users.nix") { inherit lib; };
        framework-policies = import (root + "/tests/policies.nix") { inherit lib; };
        framework-seed = import (root + "/tests/seed.nix") { inherit lib; };
        framework-modules = import (root + "/tests/modules.nix") { inherit lib; };
      }
    '';

    frameworkCli = pkgs.writeShellApplication {
      name = "framework-cli";
      runtimeInputs = [
        pkgs.bun
        pkgs.fzf
        pkgs.gitMinimal
        pkgs.nix
        nixUnit
      ];
      text = ''
        export FRAMEWORK_ROOT="${frameworkRoot}"
        export FRAMEWORK_TEST_SUITE="${frameworkTestSuite}"

        exec bun ${cliRoot}/src/main.ts "$@"
      '';
    };

    frameworkTest = pkgs.writeShellApplication {
      name = "framework-test";
      runtimeInputs = [frameworkCli];
      text = ''
        exec framework-cli test "$@"
      '';
    };

    frameworkInvariants = pkgs.writeShellApplication {
      name = "framework-invariants";
      runtimeInputs = [frameworkCli];
      text = ''
        exec framework-cli invariants "$@"
      '';
    };

    featureTrace = pkgs.writeShellApplication {
      name = "feature-trace";
      runtimeInputs = [frameworkCli];
      text = ''
        exec framework-cli trace "$@"
      '';
    };
  in {
    apps.framework-cli = {
      type = "app";
      program = lib.getExe frameworkCli;
      meta.description = "Run framework CLI";
    };

    apps.framework-test = {
      type = "app";
      program = lib.getExe frameworkTest;
      meta.description = "Run framework tests";
    };

    apps.framework-invariants = {
      type = "app";
      program = lib.getExe frameworkInvariants;
      meta.description = "Run framework invariants";
    };

    apps.feature-trace = {
      type = "app";
      program = lib.getExe featureTrace;
      meta.description = "Trace framework feature activation and effects";
    };
  };
}
