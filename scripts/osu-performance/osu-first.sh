#!/usr/bin/env bash
# Tournament-safe: does not modify the official game executable or bundled libs.
# Scope/process policy lasts only while osu! is running, and no system-wide
# forced graph quantum is set. Process-side scheduling is opt-in at launch.
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
usage: osu-first {solo|tournament|stream} [-- game-arguments...]
  solo       official osu! with background notifications suppressed
  tournament official osu! with Discord left running, no capture hooks
  stream     official osu! with SplitCast left independent
Variables:
  OSU_FIRST_BASS_PERIOD=-128|-256   (default -128; -64 crackled on neko5)
  OSU_FIRST_TIMER_SLACK_NS=1..50000 (default 1000ns)
  OSU_FIRST_CPU_UCLAMP=0..100      (default 35%, scope hint)
  OSU_FIRST_PIPEWIRE_LATENCY=128/44100 (optional request; off by default)
USAGE
}
profile="${1:-}"
case "$profile" in solo|tournament|stream) shift;; *) usage >&2; exit 64;; esac
if [[ "${1:-}" == "--" ]]; then shift; fi
period="${OSU_FIRST_BASS_PERIOD:--128}"
case "$period" in -128|-256) :;; *) echo "refusing unstable/unreviewed BASS period: $period" >&2; exit 64;; esac
slack="${OSU_FIRST_TIMER_SLACK_NS:-1000}"
[[ "$slack" =~ ^[0-9]{1,5}$ ]] && (( slack>=1 && slack<=50000 )) || { echo "invalid timer slack" >&2; exit 64; }
uclamp="${OSU_FIRST_CPU_UCLAMP:-35}"
[[ "$uclamp" =~ ^[0-9]{1,3}$ ]] && (( uclamp<=100 )) || { echo "invalid CPU uclamp" >&2; exit 64; }
command -v osu-lazer >/dev/null || { echo 'osu-lazer is not installed/in PATH' >&2; exit 127; }
command -v systemd-run >/dev/null || { echo 'systemd-run missing' >&2; exit 127; }

# Do not enable global PipeWire force quantum or replace BASS/SDL binaries.
export OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD="$period"
export SDL_VIDEODRIVER=wayland
if [[ -n "${OSU_FIRST_PIPEWIRE_LATENCY:-}" ]]; then
  [[ "$OSU_FIRST_PIPEWIRE_LATENCY" =~ ^(64|128|256|512)/(44100|48000)$ ]] || { echo 'invalid PIPEWIRE_LATENCY request' >&2; exit 64; }
  export PIPEWIRE_LATENCY="$OSU_FIRST_PIPEWIRE_LATENCY"
fi

# Notification server/Waybar are not required by the game. Their old states
# are retained and restored. No browser/Discord processes are killed.
was_mako=0
was_waybar=0
resume() {
  if (( was_waybar )); then pkill -CONT -x waybar 2>/dev/null || true; fi
  if (( was_mako )); then systemctl --user start mako.service 2>/dev/null || true; fi
}
trap resume EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if systemctl --user is-active --quiet mako.service; then
  systemctl --user stop mako.service
  was_mako=1
fi
if pgrep -x waybar >/dev/null; then
  pkill -STOP -x waybar
  was_waybar=1
fi

# The Linux scheduler retains SCHED_OTHER for all managed .NET/GC threads.
# CPUWeight increases cgroup share under contention; CPUUClampMin is a *hint*,
# not a guarantee of frequency. The game remains within the user's slice.
# Do not fall back to an unscoped launch silently on systemd failure.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
timer_exec="${OSU_FIRST_TIMER_EXEC:-$script_dir/timerslack-exec.py}"
[[ -r "$timer_exec" ]] || { echo "timer-slack helper not found: $timer_exec" >&2; exit 127; }
if [[ "$profile" == stream ]]; then
  echo 'SplitCast must be started separately; no capture is injected into osu!' >&2
fi
printf 'osu-first profile=%s BASS=%s slack=%sns uclamp=%s%%; native Wayland, official binary\n' "$profile" "$period" "$slack" "$uclamp" >&2
systemd-run --user --scope --collect --quiet \
  --property=CPUWeight=10000 \
  --property=CPUUClampMin="${uclamp}%" \
  -- \
  python3 "$timer_exec" --nanoseconds "$slack" -- osu-lazer "$@"
