#!/usr/bin/env bash
# Default: read-only narinfo audit. --strict: fail-closed signed copy to an
# isolated local store. Neither path switches a host or builds from source.
set -euo pipefail

if (( $# > 1 )); then
  echo "Expected at most one argument" >&2
  exit 2
fi

strict=0
case "${1:-}" in
  "") ;;
  --strict) strict=1 ;;
  -h|--help)
    echo "Usage: $0 [--strict]"
    echo "Default: metadata probe. Strict: require signed copy of each output."
    exit 0
    ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

locked_rev="$(jq -er '.nodes.splitcast.locked.rev' flake.lock)"
cache_url="$(
  nix eval --json '.#nixosConfigurations.neko7.config.nix.settings.extra-substituters' |
    jq -er '[.[] | select(startswith("https://github.com/tenzyu/splitcast/releases/download/nix-cache-"))] | first'
)"
cache_key="$(
  nix eval --json '.#nixosConfigurations.neko7.config.nix.settings.extra-trusted-public-keys' |
    jq -er '[.[] | select(startswith("splitcast-1:"))] | first'
)"

if [[ "$cache_url" == *"$locked_rev"* ]]; then
  revision_hint="release-name-matches-lock"
else
  revision_hint="release-name-differs-from-lock (not proof of a miss)"
fi

scratch_dir=""
if (( strict )); then
  scratch_dir="$(mktemp -d)"
  trap 'rm -rf -- "$scratch_dir"' EXIT
  isolated_store="local?root=$scratch_dir"
  # Applies to an isolated non-daemon store, never to the CI host Nix daemon.
  # Do not use --no-check-sigs or a trusted=true store URI.
  strict_config="$(printf 'experimental-features = nix-command flakes\nrequire-sigs = true\ntrusted-public-keys = %s\n' "$cache_key")"
fi

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
  printf '### SplitCast consumer binary-cache audit\n\n'
  printf -- '- Locked revision: %s\n' "$locked_rev"
  printf -- '- Configured cache: %s\n' "$cache_url"
  printf -- '- Revision hint: %s\n' "$revision_hint"
  printf -- '- Mode: %s\n\n' "$(if (( strict )); then echo signed-copy; else echo metadata-only; fi)"
  printf '%s\n' '| Package | Evaluated store path | Evidence |'
  printf '%s\n' '| --- | --- | --- |'
} | tee -a "$summary"

failures=0
for name in splitcast splitcast-web splitcast-obs; do
  expr="let f = builtins.getFlake (toString ./.); in f.inputs.splitcast.packages.x86_64-linux.\"${name}\".outPath"
  store_path="$(nix eval --impure --raw --expr "$expr")"
  outcome="NOT-CONFIRMED"
  if timeout 20s nix path-info --store "$cache_url" "$store_path" >/dev/null 2>&1; then
    outcome="NARINFO-QUERY-OK"
    if (( strict )); then
      if NIX_CONFIG="$strict_config" timeout 300s nix copy \
        --from "$cache_url" --to "$isolated_store" "$store_path" \
        >"$scratch_dir/${name}.log" 2>&1 &&
        NIX_CONFIG="$strict_config" nix path-info --store "$isolated_store" "$store_path" >/dev/null; then
        outcome="SIGNED-COPY-OK"
      else
        outcome="COPY-FAILED"
        echo "::warning::$name: signed isolated copy failed" >&2
        tail -n 12 "$scratch_dir/${name}.log" >&2 || true
      fi
    fi
  fi
  if (( strict )) && [[ "$outcome" != "SIGNED-COPY-OK" ]]; then
    failures=$((failures + 1))
  fi
  printf '%s: %s [%s]\n' "$name" "$store_path" "$outcome"
  printf '| %s | %s | %s |\n' "$name" "$store_path" "$outcome" >> "$summary"
done

if (( strict )); then
  if (( failures )); then
    echo "::error::$failures SplitCast outputs failed strict signed-copy verification" >&2
    printf '\nStrict signed-copy verification failed for %s output(s).\n' "$failures" | tee -a "$summary"
    exit 1
  fi
  printf '\nSIGNED-COPY-OK: Nix accepted the closure into a temporary local store with require-sigs=true and the configured public key. This does NOT prove neko7 runtime substitution.\n' | tee -a "$summary"
else
  printf '\nNARINFO-QUERY-OK means metadata reachability only. NOT-CONFIRMED can mean missing path, network failure, or timeout. workflow_dispatch cache_strict=true verifies signed copies; it may fail if cache publication is incomplete.\n' | tee -a "$summary"
fi
