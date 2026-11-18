#!/usr/bin/env bash
# Keep the wrapper alive so an EXIT trap can undo the optional Hyprland mode.
set -euo pipefail
game_pid=""
restore_hypr=0

cleanup() {
  if (( restore_hypr )); then
    hypr-gaming-mode off || true
  fi
}
terminate() {
  local status="$1"
  trap - INT TERM
  if [[ -n "$game_pid" ]]; then
    kill -TERM "$game_pid" 2>/dev/null || true
    wait "$game_pid" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'terminate 130' INT
trap 'terminate 143' TERM

if command -v hypr-gaming-mode >/dev/null 2>&1; then
  if hypr-gaming-mode on; then restore_hypr=1; fi
fi

gamemoderun gamescope \
  --backend "${GAMESCOPE_BACKEND:-sdl}" \
  --steam --rt -f \
  -W "${GAMESCOPE_WIDTH:-1366}" \
  -H "${GAMESCOPE_HEIGHT:-768}" \
  -r "${GAMESCOPE_REFRESH:-60}" \
  -- steam "$@" &
game_pid="$!"
rc=0
wait "$game_pid" || rc="$?"
exit "$rc"
