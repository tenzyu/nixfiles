#!/usr/bin/env bash
# Tournament-safe: official osu! binary and bundled libraries remain untouched.
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
usage: osu-first {solo|tournament|stream|doctor} [-- game-arguments...]
  solo/tournament/stream: official osu!; Discord and SplitCast are never killed
  doctor: read-only launcher dependency and cgroup preflight (does not start osu!)
Variables:
  OSU_FIRST_BASS_PERIOD=-128|-256        (default -128; -64 crackled on neko5)
  OSU_FIRST_TIMER_SLACK_NS=1..50000      (default 1000ns)
  OSU_FIRST_CPU_UCLAMP=0..100           (default 0; no forced utilization)
  OSU_FIRST_CPU_WEIGHT=1..10000         (default 500; fair cgroup share)
  OSU_FIRST_SCOPE_MODE=auto|required|off (default auto)
  OSU_FIRST_TIMER_MODE=auto|required|off (default auto)
  OSU_FIRST_SUPPRESS_UI=0|1             (default 1)
  OSU_FIRST_PIPEWIRE_LATENCY=128/48000  (optional request; default off)
USAGE
}
profile="${1:-}"
case "$profile" in solo|tournament|stream|doctor) shift;; *) usage >&2; exit 64;; esac
if [[ "${1:-}" == "--" ]]; then shift; fi
period="${OSU_FIRST_BASS_PERIOD:--128}"
case "$period" in -128|-256) :;; *) echo "refusing unstable/unreviewed BASS period: $period" >&2; exit 64;; esac
slack="${OSU_FIRST_TIMER_SLACK_NS:-1000}"
[[ "$slack" =~ ^[0-9]{1,5}$ ]] && (( slack>=1 && slack<=50000 )) || { echo 'invalid timer slack' >&2; exit 64; }
uclamp="${OSU_FIRST_CPU_UCLAMP:-0}"
[[ "$uclamp" =~ ^[0-9]{1,3}$ ]] && (( uclamp<=100 )) || { echo 'invalid CPU uclamp' >&2; exit 64; }
weight="${OSU_FIRST_CPU_WEIGHT:-500}"
[[ "$weight" =~ ^[0-9]{1,5}$ ]] && (( weight>=1 && weight<=10000 )) || { echo 'invalid CPU weight' >&2; exit 64; }
scope_mode="${OSU_FIRST_SCOPE_MODE:-auto}"
timer_mode="${OSU_FIRST_TIMER_MODE:-auto}"
suppress_ui="${OSU_FIRST_SUPPRESS_UI:-1}"
case "$scope_mode" in auto|required|off) :;; *) echo 'invalid scope mode' >&2; exit 64;; esac
case "$timer_mode" in auto|required|off) :;; *) echo 'invalid timer mode' >&2; exit 64;; esac
case "$suppress_ui" in 0|1) :;; *) echo 'invalid UI mode' >&2; exit 64;; esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
timer_exec="${OSU_FIRST_TIMER_EXEC:-$script_dir/timerslack-exec.py}"
game_cmd="$(command -v osu-lazer || true)"
if [[ -z "$game_cmd" ]]; then
  echo 'osu-lazer is missing from PATH; try `command -v osu-lazer` or the raw desktop entry' >&2
  exit 127
fi

if [[ "$profile" == doctor ]]; then
  printf 'game=%s\nPATH=%s\ntimer_helper=%s\nscope_mode=%s timer_mode=%s\n' \
    "${game_cmd:-MISSING}" "$PATH" "$timer_exec" "$scope_mode" "$timer_mode"
  if [[ "$timer_mode" != off ]]; then
    if [[ -r "$timer_exec" ]] && command -v python3 >/dev/null; then
      python3 "$timer_exec" --nanoseconds "$slack" -- true || echo 'timer preflight failed (optional when timer_mode=auto)' >&2
    else
      echo 'timer helper or python3 not available' >&2
    fi
  fi
  if [[ "$scope_mode" != off ]]; then
    if command -v systemd-run >/dev/null; then
      systemd-run --user --scope --collect --quiet \
        --property=CPUWeight="$weight" --property=CPUUClampMin="${uclamp}%" -- true \
        || echo 'scope preflight failed (optional when scope_mode=auto)' >&2
    else
      echo 'systemd-run not available' >&2
    fi
  fi
  [[ -n "$game_cmd" ]]
  exit $?
fi

# Do not alter global PipeWire quantum, game files, or BASS/SDL libraries.
export OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD="$period"
export SDL_VIDEODRIVER=wayland
if [[ -n "${OSU_FIRST_PIPEWIRE_LATENCY:-}" ]]; then
  [[ "$OSU_FIRST_PIPEWIRE_LATENCY" =~ ^(64|128|256|512)/(44100|48000)$ ]] || { echo 'invalid PIPEWIRE_LATENCY request' >&2; exit 64; }
  export PIPEWIRE_LATENCY="$OSU_FIRST_PIPEWIRE_LATENCY"
fi

launch=("$game_cmd" "$@")
if [[ "$timer_mode" != off ]]; then
  if [[ -r "$timer_exec" ]] && command -v python3 >/dev/null; then
    if [[ "$timer_mode" == auto ]]; then
      launch=(python3 "$timer_exec" --best-effort --nanoseconds "$slack" -- "${launch[@]}")
    else
      launch=(python3 "$timer_exec" --nanoseconds "$slack" -- "${launch[@]}")
    fi
  elif [[ "$timer_mode" == required ]]; then
    echo "required timer helper unavailable: $timer_exec" >&2
    exit 127
  else
    echo "osu-first: timer helper unavailable; running without timer override" >&2
  fi
fi

was_mako=0
was_waybar=0
marker_dir=''
resume() {
  if (( was_waybar )); then pkill -CONT -x waybar 2>/dev/null || true; fi
  if (( was_mako )); then systemctl --user start mako.service 2>/dev/null || true; fi
  if [[ -n "$marker_dir" ]]; then rm -rf -- "$marker_dir"; fi
}
trap resume EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if [[ "$suppress_ui" == 1 ]]; then
  if systemctl --user is-active --quiet mako.service 2>/dev/null; then
    systemctl --user stop mako.service
    was_mako=1
  fi
  if pgrep -x waybar >/dev/null 2>&1; then
    pkill -STOP -x waybar
    was_waybar=1
  fi
fi

if [[ "$profile" == stream ]]; then
  echo 'SplitCast starts independently; no capture is injected into osu!' >&2
fi
printf 'osu-first profile=%s BASS=%s slack=%sns uclamp=%s%% weight=%s scope=%s timer=%s\n' \
  "$profile" "$period" "$slack" "$uclamp" "$weight" "$scope_mode" "$timer_mode" >&2

# A scope launch is synchronous. An exit code alone cannot distinguish an
# unavailable cgroup from a game crash. The marker is written by the *child*
# before exec: only a failed scope setup is retried without a scope.
if [[ "$scope_mode" != off ]]; then
  if command -v systemd-run >/dev/null; then
    marker_dir="$(mktemp -d)"
    marker="$marker_dir/started"
    if systemd-run --user --scope --collect --quiet \
        --property=CPUWeight="$weight" --property=CPUUClampMin="${uclamp}%" \
        -- bash -c 'printf started > "$1" || exit 78; shift; exec "$@"' -- "$marker" "${launch[@]}"; then
      rc=0
    else
      rc=$?
    fi
    if [[ -e "$marker" ]]; then
      exit "$rc" # the game (or timer helper) ran: never start a second instance
    fi
    echo "osu-first: user scope could not start (status $rc)" >&2
  else
    echo 'osu-first: systemd-run not found' >&2
  fi
  if [[ "$scope_mode" == required ]]; then
    echo 'osu-first: scope is required; game NOT launched' >&2
    exit 1
  fi
  echo 'osu-first: starting official game without cgroup overrides' >&2
fi
"${launch[@]}"
