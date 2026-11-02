#!/usr/bin/env bash
set -eu
runtime=$(mktemp -d /tmp/opencode/splitcast-obs-runtime.XXXXXXXX)
chmod 700 "$runtime"
export XDG_RUNTIME_DIR="$runtime"
export PIPEWIRE_RUNTIME_DIR="$runtime"
export PULSE_RUNTIME_PATH="$runtime/pulse"
export XDG_CONFIG_HOME="$runtime/config"
export XDG_CACHE_HOME="$runtime/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
Xvfb -displayfd 3 -screen 0 1920x1080x24 -nolisten tcp 3>"$runtime/display" >"$runtime/xvfb.log" 2>&1 &
pids+=("$!")
pipewire >"$runtime/pipewire.log" 2>&1 &
pids+=("$!")
pipewire-pulse >"$runtime/pipewire-pulse.log" 2>&1 &
pids+=("$!")
wireplumber >"$runtime/wireplumber.log" 2>&1 &
pids+=("$!")
for i in $(seq 1 50); do
  if test -s "$runtime/display" && pactl info >"$runtime/pactl-info" 2>/dev/null; then break; fi
  sleep 0.2
done
test -s "$runtime/display"
export DISPLAY=":$(cat "$runtime/display")"
printf 'Runtime: %s\nDisplay: %s\n' "$runtime" "$DISPLAY"
pactl info
"$@"
