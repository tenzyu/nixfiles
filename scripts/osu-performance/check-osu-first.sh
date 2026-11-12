#!/usr/bin/env bash
# Read-only structural and source-integrity acceptance checks.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
cd "$repo"
bash -n scripts/osu-performance/osu-first.sh
python3 -m py_compile scripts/osu-performance/timerslack-exec.py
# Verify this change has no patch to upstream game binaries or libraries.
git diff --name-only -- HEAD | while IFS= read -r file; do
  case "$file" in
    modules/*|scripts/osu-performance/*|packages/splitcast-rs/*|docs/graphics-streaming/*) ;;
    *) printf 'unexpected changed file: %s\n' "$file" >&2; exit 1;;
  esac
done
# Full compile and Nix evaluation are mandatory before enabling Rust.
if command -v cargo >/dev/null; then
  (cd packages/splitcast-rs && cargo test --locked --offline)
else
  echo 'UNVERIFIED: rustc/cargo unavailable; Rust build/test not performed' >&2
fi
if command -v nix >/dev/null; then
  nix flake check --no-build
else
  echo 'UNVERIFIED: Nix unavailable; flake evaluation not performed' >&2
fi
printf 'Source integrity/available checks completed (not a performance benchmark)\n'
