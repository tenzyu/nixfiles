#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"
host=${SPLITCAST_BUILD_HOST:-neko7}
case "$host" in
  *[!a-zA-Z0-9_.@-]*|'') printf 'Invalid SSH host\n' >&2; exit 2 ;;
esac
case "${1:-}" in
  snapshot|build|test) action=$1 ;;
  *) printf 'Usage: bash scripts/splitcast/remote-dev.sh snapshot|build|test\n' >&2; exit 2 ;;
esac

remote=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$host" 'mktemp -d "$HOME/.cache/splitcast-dev.XXXXXXXX"')
case "$remote" in
  /home/*/.cache/splitcast-dev.*) ;;
  *) printf 'Unexpected remote directory; refusing transfer\n' >&2; exit 1 ;;
esac
printf 'Snapshot: %s:%s\n' "$host" "$remote" >&2
git archive HEAD | ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$host" "tar -xf - -C '$remote'"
tar --exclude='__pycache__' --exclude='*.pyc' -cf - \
  modules/00-hosts/neko5/configuration.nix modules/00-hosts/neko7/configuration.nix \
  modules/50-features/packages-desktop.nix modules/50-features/splitcast-capture.nix \
  modules/50-features/splitcast-production.nix modules/50-features/splitcast-checks.nix \
  modules/50-features/splitcast-packages.nix modules/50-features/splitcast \
  packages/splitcast scripts/splitcast | \
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$host" "tar -xf - -C '$remote'"

case "$action" in
  snapshot) ;;
  build)
    ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$host" \
      "nix build --no-link --print-build-logs --max-jobs 1 --cores 2 --print-out-paths 'path:$remote#splitcast'"
    ;;
  test)
    ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$host" \
      "set -e; python=\$(nix eval --raw 'path:$remote#packages.x86_64-linux.splitcast.python.outPath'); rnnoise=\$(nix eval --raw 'path:$remote#packages.x86_64-linux.splitcast.rnnoise.outPath'); systemd-run --user --scope -p CPUQuota=200% -p MemoryHigh=3G -- nix shell --inputs-from 'path:$remote' nixpkgs#ffmpeg-full nixpkgs#mediamtx --command env PYTHONPATH='$remote/packages/splitcast' SPLITCAST_RNNOISE_PLUGIN=\"\$rnnoise/lib/ladspa/librnnoise_ladspa.so\" \"\$python/bin/python\" -m unittest discover -s '$remote/packages/splitcast/tests' -v"
    ;;
esac
