#!/usr/bin/env bash
# Read-only structural and source-integrity acceptance checks.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
cd "$repo"
bash -n scripts/osu-performance/osu-first.sh
bash -n scripts/osu-performance/draw-observe.sh
bash scripts/osu-performance/test-draw-observe.sh
python3 -c 'from pathlib import Path; p=Path("scripts/osu-performance/timerslack-exec.py"); compile(p.read_text(), str(p), "exec")'
bash scripts/osu-performance/test-osu-first.sh
# Verify this change has no patch to upstream game binaries or libraries.
git diff --name-only HEAD -- | while IFS= read -r file; do
  case "$file" in
    modules/*|scripts/osu-performance/*|docs/*) ;;
    *) printf 'unexpected changed file: %s\n' "$file" >&2; exit 1;;
  esac
done
# SplitCast owns its Rust verification in its independent flake.
if command -v nix >/dev/null; then
  nix flake check --no-build
else
  echo 'UNVERIFIED: Nix unavailable; flake evaluation not performed' >&2
fi
printf 'Source integrity/available checks completed (not a performance benchmark)\n'
