#!/usr/bin/env bash
# Read-only source-path cache probe. A miss is diagnostic, not a build failure.
set -euo pipefail

locked_rev="$(jq -er '.nodes.splitcast.locked.rev' flake.lock)"
cache_url="$(
  nix eval --json '.#nixosConfigurations.neko7.config.nix.settings.extra-substituters' |
    jq -er '[.[] | select(startswith("https://github.com/tenzyu/splitcast/releases/download/nix-cache-"))] | first'
)"

if [[ "$cache_url" == *"$locked_rev"* ]]; then
  revision_hint="release-name-matches-lock"
else
  revision_hint="release-name-differs-from-lock (not proof of a store-path miss)"
fi

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
  printf '### SplitCast consumer binary-cache probe\n\n'
  printf -- '- Locked input revision: `%s`\n' "$locked_rev"
  printf -- '- Cache URL: `%s`\n' "$cache_url"
  printf -- '- Revision hint: %s\n\n' "$revision_hint"
  printf '%s\n' '| Input package | Evaluated output path | Release cache |'
  printf '%s\n' '| --- | --- | --- |'
} | tee -a "$summary"

for name in splitcast splitcast-web splitcast-obs; do
  # Evaluate the actual input package path; a matching git revision by itself
  # cannot establish that a signed NAR is present in the release.
  expr="let f = builtins.getFlake (toString ./.); in f.inputs.splitcast.packages.x86_64-linux.\"${name}\".outPath"
  store_path="$(nix eval --impure --raw --expr "$expr")"
  outcome="NOT-CONFIRMED"
  if timeout 20s nix path-info --store "$cache_url" "$store_path" >/dev/null 2>&1; then
    outcome="AVAILABLE"
  fi
  printf '%s: %s [%s]\n' "$name" "$store_path" "$outcome"
  printf '| `%s` | `%s` | %s |\n' "$name" "$store_path" "$outcome" >> "$summary"
done

printf '\nNOT-CONFIRMED includes missing paths, network errors and timeouts; it is not evidence that the package cannot build. Nothing is copied or activated.\n' | tee -a "$summary"
