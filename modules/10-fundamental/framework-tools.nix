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

    frameworkModuleRoot = ../_internal/framework;
    cliRoot = ../../tools/framework-cli;
    traceLib = ../../tools/framework-cli/feature-trace.nix;

    frameworkTestSuite = pkgs.writeText "framework-tests.nix" ''
      let
        lib = import ${inputs.nixpkgs}/lib;
        root = ${frameworkModuleRoot};
        # This suite is evaluated from a /nix/store copy of the internal
        # framework. External tools and fundamentals must be independent
        # store inputs, not relative imports from the isolated test root.
        policyLib = import ${./_policy/lib.nix};
        traceLib = import ${../../tools/framework-cli/feature-trace.nix};
      in {
        framework-features = import (root + "/tests/features.nix") { inherit lib; };
        framework-users = import (root + "/tests/users.nix") { inherit lib; };
        framework-policies = import (root + "/tests/policies.nix") { inherit lib policyLib; };
        framework-seed = import (root + "/tests/seed.nix") { inherit lib; };
        framework-modules = import (root + "/tests/modules.nix") { inherit lib; };
        framework-trace = import (root + "/tests/trace.nix") { inherit lib traceLib; };
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
        export FEATURE_TRACE_LIB="${traceLib}"
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
    checks.framework-cli =
      pkgs.runCommand "framework-cli-check" {
        src = pkgs.lib.cleanSource cliRoot;
        nativeBuildInputs = [pkgs.bun pkgs.typescript];
      } ''
        set -euo pipefail
        cp -r "$src" ./cli
        chmod -R u+w ./cli
        cd ./cli
        tsc --noEmit
        bun test
        touch "$out"
      '';

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
