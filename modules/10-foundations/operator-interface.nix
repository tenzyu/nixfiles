{lib, options, self, ...}: let
  domain = (import ../../lib/operator/feature-inventory.nix {inherit lib;}) {
    flake = self;
    hostDefinitions = options.configurations.nixos.definitionsWithLocations;
    homeDefinitions = options.configurations.homeManager.definitionsWithLocations;
    # flake is a submodule option; the outer definitions retain the original
    # declaration locations, unlike the synthetic evaluated module wrappers.
    moduleDefinitions = options.flake.definitionsWithLocations;
  };
  # The canonical local registrations and both evaluated scopes must be
  # navigable. Native origins are read from a real NixOS/HM evaluation.
  matches = scope: lib.any (row:
    row.configuration == "neko5" && row.scope == scope && row.feature == "jay"
    && row.enabled
    && lib.elem "modules/00-hosts/neko5/configuration.nix" row.sources.selection
    && lib.elem "modules/50-features/desktop/jay.nix" row.sources.registration
    && (scope != "home" || (row.user == "tenzyu"
      && lib.elem "modules/60-integrations/desktop/jay-cclip.nix" row.sources.registration)))
    domain.features;
  nativeOriginsPresent = domain.origins.nixos.neko5.system.jay.locations != []
    && domain.origins.nixos.neko5.home.tenzyu.jay.locations != [];
in {
  flake.operator = domain;
  perSystem = {pkgs, system, ...}: let
    browser = pkgs.writeShellApplication {
      name = "nixfiles-feature-browser";
      runtimeInputs = [pkgs.jq pkgs.fzf pkgs.ripgrep pkgs.bat pkgs.gitMinimal pkgs.coreutils];
      text = builtins.readFile ../../tools/operator/feature-browser.sh;
    };
    gc = pkgs.writeShellApplication {
      name = "nixfiles-store-gc";
      runtimeInputs = [pkgs.coreutils pkgs.less];
      text = builtins.readFile ../../lib/operator/store-policy.sh + "\n" + builtins.readFile ../../tools/operator/store-gc.sh;
    };
    operator = pkgs.writeShellApplication {
      name = "nixfiles-operator";
      runtimeInputs = [browser gc pkgs.just pkgs.fzf pkgs.bash pkgs.gitMinimal pkgs.coreutils pkgs.less pkgs.jq];
      text = ''
        root=$(git rev-parse --show-toplevel)
        [[ -f "$root/flake.nix" && -f "$root/tools/operator/justfile" ]] || {
          echo 'Run from the nixfiles Git checkout.' >&2; exit 1;
        }
        cd "$root"
        if (( $# == 0 )); then
          exec just --working-directory "$root" --justfile "$root/tools/operator/justfile" --chooser 'fzf --no-multi --prompt="Nixfiles> "' --choose
        fi
        exec just --working-directory "$root" --justfile "$root/tools/operator/justfile" "$@"
      '';
    };
  in lib.mkIf (system == "x86_64-linux") {
    packages.operator = operator;
    apps = {
      operator = {type = "app"; program = "${operator}/bin/nixfiles-operator";};
      operator-inspect = {type = "app"; program = "${pkgs.nix-inspect}/bin/nix-inspect";};
      operator-diff = {type = "app"; program = "${pkgs.nvd}/bin/nvd";};
    };
    validationChecks.operator-interface =
      assert lib.assertMsg (matches "system" && matches "home" && nativeOriginsPresent)
        "Feature inventory lost the real Jay selection, registration or native origins";
      pkgs.runCommand "operator-interface" {nativeBuildInputs = [pkgs.just pkgs.bash pkgs.coreutils pkgs.gitMinimal pkgs.jq pkgs.diffutils];} ''
        just --justfile ${../../tools/operator/justfile} --list
        just --justfile ${../../tools/operator/justfile} --dry-run store-clean
        test -x ${operator}/bin/nixfiles-operator
        test -x ${browser}/bin/nixfiles-feature-browser
        status=0
        ${gc}/bin/nixfiles-store-gc </dev/null || status=$?
        test "$status" = 2

        bash ${../../tools/operator/test-feature-browser.sh} ${../../tools/operator/feature-browser.sh}

        # Test only our admission rule; never run actual GC in CI.
        source ${../../lib/operator/store-policy.sh}
        mkdir generation-a generation-b
        ln -s "$PWD/generation-a" current
        ln -s "$PWD/generation-a" booted
        ln -s "$PWD/generation-a" profile
        test "$(consistent_generation current booted profile)" = "$PWD/generation-a"
        # Each independent mismatch or missing link must fail closed.
        for link in current booted profile; do
          ln -sfn "$PWD/generation-b" "$link"
          if consistent_generation current booted profile; then exit 1; fi
          rm "$link"
          if consistent_generation current booted profile; then exit 1; fi
          ln -s "$PWD/generation-a" "$link"
        done
        test "$(consistent_generation current booted profile)" = "$PWD/generation-a"
        touch "$out"
      '';
  };
}
