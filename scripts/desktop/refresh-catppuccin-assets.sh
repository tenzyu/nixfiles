#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
dest=assets/catppuccin
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# Materialize the locked upstream recipes only on explicit dependency updates.
# The normal evaluator consumes the resulting files, not these derivations.
base='(builtins.getFlake (toString ./.)).inputs.catppuccin'
nix_eval() {
  nix eval --impure --no-write-lock-file --no-update-lock-file "$@"
}
build_port() {
  nix build --impure --no-write-lock-file --no-update-lock-file --no-link --print-out-paths \
    --expr "$base.packages.x86_64-linux.$1"
}

nix_eval --json --expr "let c = $base; in { catppuccin = c.narHash; nixpkgs = c.inputs.nixpkgs.narHash; }" \
  > "$stage/source.json"
for port in firefox starship palette; do
  out=$(build_port "$port")
  mkdir -p "$stage/$port"
  case "$port" in
    firefox) cp "$out/themes.json" "$stage/$port/" ;;
    starship) cp "$out/"{latte,frappe,macchiato,mocha}.toml "$stage/$port/" ;;
    palette) cp "$out/palette.json" "$stage/$port/" ;;
  esac
  src=$(build_port "$port.src")
  cp "$src/LICENSE" "$stage/$port/LICENSE"
done

# Nothing in the repository is changed until every source is available.
mkdir -p "$dest"
cp -r --remove-destination "$stage/." "$dest/"
# Stage explicitly when ready; Git flakes do not include untracked paths.
printf 'Refreshed %s; review and stage the snapshot with flake.lock.\n' "$dest"
