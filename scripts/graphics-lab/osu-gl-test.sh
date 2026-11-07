#!/usr/bin/env bash
# Opt-in experiment: no system changes; does not select Vulkan/Zink/XWayland.
set -euo pipefail
if (( $# < 1 )); then echo 'usage: osu-gl-test.sh COMMAND [ARGS...]' >&2; exit 2; fi
out="${XDG_STATE_HOME:-$HOME/.local/state}/osu-gl-tests"
mkdir -p -- "$out"
log="$out/$(date -u +%Y%m%dT%H%M%SZ).txt"
{
  printf 'session=%s\n' "${XDG_SESSION_TYPE:-unknown}"
  printf 'kernel='; uname -r
  printf 'command='; printf '%q ' "$@"; printf '\n'
  printf 'renderer=opengl\nsurface=OpenGL\nSDL_VIDEODRIVER=wayland\n'
} > "$log"
printf 'Diagnostic metadata: %s\n' "$log"
exec env OSU_GRAPHICS_RENDERER=opengl OSU_GRAPHICS_SURFACE=OpenGL SDL_VIDEODRIVER=wayland "$@"
