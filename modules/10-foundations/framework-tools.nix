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

    configurationsModuleRoot = ../_internal/configurations;
    cliRoot = ../../tools/framework-cli;
    traceLib = ../../tools/framework-cli/feature-trace.nix;

    frameworkTestSuite = pkgs.writeText "framework-tests.nix" ''
      let
        lib = import ${inputs.nixpkgs}/lib;
        root = ${configurationsModuleRoot};
        # This suite is evaluated from a /nix/store copy of the internal
        # framework. External tools and fundamentals must be independent
        # store inputs, not relative imports from the isolated test root.
        policyLib = import (${../..} + "/modules/10-foundations/_policy/lib.nix");
        sharedLibRoot = ${../../lib};
        traceLib = import ${traceLib};
      in {
        shared-lib = import (sharedLibRoot + "/tests.nix") { inherit lib; };
        framework-features = import (root + "/tests/features.nix") { inherit lib; };
        framework-users = import (root + "/tests/users.nix") { inherit lib; };
        framework-policies = import (root + "/tests/policies.nix") { inherit lib policyLib; };
        framework-seed = import (root + "/tests/seed.nix") {
          inherit lib;
          composition = import (sharedLibRoot + "/composition.nix") {inherit lib;};
        };
        framework-modules = import (root + "/tests/modules.nix") { inherit lib; };
        framework-trace = import (root + "/tests/trace.nix") { inherit lib traceLib; };
        integration-steam-hyprland = import (root + "/tests/integrations-steam.nix") {
          inherit lib;
          integrationModule = (import ${../60-integrations/desktop/steam-hyprland.nix}).flake.modules.homeManager.steam;
        };
        integration-parsec-hyprland = import (root + "/tests/integrations.nix") {
          inherit lib;
          integrationModule = (import ${../60-integrations/desktop/parsec-hyprland.nix}).flake.modules.homeManager.parsec;
        };
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
        cli=${lib.getExe frameworkCli}
        "$cli" trace --help >help
        grep -q -- '--why OPTION_PATH' help
        if "$cli" trace --host --json >output 2>error; then
          echo 'packaged CLI accepted an incomplete trace' >&2
          exit 1
        fi
        test ! -s output
        grep -q -- '--host requires a value' error
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
