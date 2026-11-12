#!/usr/bin/env bash
# Opt-in osu!lazer BASS device-period launch. Never changes system/PipeWire settings.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  bash scripts/osu-performance/bass-period-lab.sh status
  bash scripts/osu-performance/bass-period-lab.sh baseline [-- GAME_ARGS...]
  bash scripts/osu-performance/bass-period-lab.sh -256 [-- GAME_ARGS...]

The same nixfiles osu-lazer launcher is used for both conditions.
- baseline: remove OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD for this process only.
- -256: request BASS device period of 256 samples, for this process only.
No global PipeWire quantum, Nix settings, sound devices, or game configuration change.
Stop the game normally before changing the condition.
-128/-64 are intentionally not offered: documented Linux crashes under some mods.
HELP
}

check_osu_closed() {
  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -u "$(id -u)" -x 'osu!' >/dev/null 2>&1 ||
       pgrep -u "$(id -u)" -x 'osu-lazer' >/dev/null 2>&1; then
      printf '%s\n' 'An osu! process appears to be running. Exit osu! normally before using this launcher.' >&2
      exit 3
    fi
  fi
}

# CLI only. Never automatically changes a process or global audio settings.
case "${1:-}" in
  help|-h|--help|'') usage;exit 0;;
  status)
    printf 'Launcher: %s\n' "$(command -v osu-lazer || printf 'unavailable')"
    printf 'BASS override in this shell: %s\n' "${OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD:-unset}"
    if command -v pw-metadata >/dev/null 2>&1; then
      printf 'PipeWire force-quantum metadata (0 means automatic; NOT necessarily 1024):\n'
      pw-metadata -n settings 0 clock.force-quantum || true
    fi
    if command -v pgrep >/dev/null 2>&1; then
      pgrep -u "$(id -u)" -a -x 'osu!' || true
    fi
    exit 0;;
  baseline)
    mode=baseline;shift;;
  -256)
    mode=-256;shift;;
  *) usage >&2;exit 2;;
esac

if [[ "${1:-}" == '--' ]]; then shift;fi
command -v osu-lazer >/dev/null 2>&1 || { echo 'osu-lazer unavailable: activate home-manager / nixfiles osu-lazer feature.' >&2; exit 127; }
check_osu_closed

if [[ "$mode" == baseline ]]; then
  printf '%s\n' 'Launching standard osu!lazer (BASS environment override cleared).' >&2
  exec env -u OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD osu-lazer "$@"
else
  printf '%s\n' 'Launching osu!lazer with BASS period request -256 samples.' >&2
  printf '%s\n' 'This is experimental and may cause audio crackling or crashes with some mods.' >&2
  exec env OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-256 osu-lazer "$@"
fi
