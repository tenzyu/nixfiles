{lib, ...}: {
  perSystem = {pkgs, ...}: {
    checks.deprecated-patterns =
      pkgs.runCommand "check-deprecated-patterns" {
        src = lib.cleanSource ../..;
        nativeBuildInputs = [pkgs.ripgrep];
      } ''
        set -euo pipefail
        cd "$src"

        bad=0

        if rg -n \
          -g '!modules/10-framework/checks.nix' \
          -g '!result' \
          -g '!result-*' \
          -e 'flake\.effects' \
          -e 'feature\.system' \
          -e 'feature\.users' \
          -e 'resolveClosure' \
          -e 'callProjection' \
          -e 'projectionToModule' \
          -e '99-flake-runtime' \
          modules README.md; then
          bad=1
        fi

        if find modules/ -name 'zsh copy.nix' 2>/dev/null | grep -q .; then
          echo "error: modules/zsh copy.nix must not exist" >&2
          bad=1
        fi

        if [ "$bad" -ne 0 ]; then
          echo "failing check: deprecated patterns must be removed" >&2
          exit 1
        fi

        mkdir -p "$out"
        echo "deprecated-patterns: ok" > "$out/result"
      '';

    checks.feature-name-shape =
      pkgs.runCommand "check-feature-name-shape" {
        src = lib.cleanSource ../..;
      } ''
        set -euo pipefail
        cd "$src"

        bad=0
        for f in $(find modules/ -name '*.nix'); do
          leaf="$(basename "$f" .nix)"
          case "$leaf" in
            _*)
              ;;
            *[!a-z0-9-]*)
              echo "error: $f has non-kebab-case feature name '$leaf'" >&2
              bad=1
              ;;
            -*)
              echo "error: $f has feature name starting with '-' ($leaf)" >&2
              bad=1
              ;;
            *-)
              echo "error: $f has feature name ending with '-' ($leaf)" >&2
              bad=1
              ;;
          esac
        done

        if [ "$bad" -ne 0 ]; then
          echo "failing check: feature name shape" >&2
          exit 1
        fi

        mkdir -p "$out"
        echo "feature-name-shape: ok" > "$out/result"
      '';
  };
}
