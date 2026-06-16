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

    frameworkTestSuite = pkgs.writeText "framework-tests.nix" ''
      let
        lib = import ${inputs.nixpkgs}/lib;
        root = ${./.};
      in {
        framework-features = import (root + "/tests/features.nix") { inherit lib; };
        framework-users = import (root + "/tests/users.nix") { inherit lib; };
        framework-policies = import (root + "/tests/policies.nix") { inherit lib; };
        framework-seed = import (root + "/tests/seed.nix") { inherit lib; };
        framework-modules = import (root + "/tests/modules.nix") { inherit lib; };
      }
    '';

    frameworkTest = pkgs.writeShellApplication {
      name = "framework-test";
      runtimeInputs = [
        nixUnit
        pkgs.coreutils
        pkgs.gitMinimal
        pkgs.nix
      ];

      text = ''
        tmpdir="''${TMPDIR:-/tmp}"
        gc_roots="$(mktemp -d "$tmpdir/framework-test-gc-roots.XXXXXX")"
        trap 'rm -rf -- "$gc_roots"' EXIT

        echo "== framework nix-unit =="
        nix-unit --show-trace --gc-roots-dir "$gc_roots" ${frameworkTestSuite}

        repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
        flake_ref="path:$repo"

        check_eq() {
          name="$1"
          expected="$2"
          actual="$3"

          if [ "$actual" != "$expected" ]; then
            echo "FAIL $name: expected $expected, got $actual" >&2
            exit 1
          fi

          echo "OK   $name: $actual"
        }

        echo
        echo "== framework invariants =="

        check_eq \
          "debug.options.configurations.nixos.type.name" \
          "attrsOf" \
          "$(nix eval --raw "$flake_ref#debug.options.configurations.nixos.type.name")"

        check_eq \
          "debug.options.configurations.homeManager.type.name" \
          "attrsOf" \
          "$(nix eval --raw "$flake_ref#debug.options.configurations.homeManager.type.name")"

        seed_enable_type="$(
          nix eval --raw --impure --expr "
            let
              flake = builtins.getFlake \"path:$repo\";
              nixosOptions = flake.debug.options.configurations.nixos;
              neko5ModuleOpts = nixosOptions.type.getSubOptions [ \"neko5\" ];
              localOpts = neko5ModuleOpts.module.type.getSubOptions [];
              tenzyuFeatureOpts = localOpts.local.users.type.getSubOptions [ \"tenzyu\" ];
            in
              tenzyuFeatureOpts.features.steam.enable.type.name
          "
        )"

        check_eq \
          "local.users.tenzyu.features.steam.enable.type.name" \
          "nullOr" \
          "$seed_enable_type"

        echo
        echo "framework-test: ok"
      '';
    };
  in {
    apps.framework-test = {
      type = "app";
      program = lib.getExe frameworkTest;
      meta.description = "Run framework nix-unit tests and framework invariants";
    };
  };
}
