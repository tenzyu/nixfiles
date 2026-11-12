#!/usr/bin/env bash
# Strictly opt-in; does not change permanent PipeWire/Nix configuration.
set -euo pipefail
umask 077
PW_METADATA=${PW_METADATA:-pw-metadata}
FLOCK=${FLOCK:-flock}

help() {
  cat <<'HELP'
Usage:
  osu-audio-quantum-lab status
  osu-audio-quantum-lab run {256|128|64|32} -- COMMAND [ARG ...]
  osu-audio-quantum-lab restore

This changes the shared PipeWire clock.force-quantum while COMMAND is running,
then restores automatic selection (0). It never changes system/Nix config.
Run while osu! is already open with `... run 256 -- sleep 180` if desired.
After a hard kill or loss of power, `restore` explicitly sets 0.
Do not use while recording/streaming or other latency-sensitive audio is active.
HELP
}
read_force() {
  local output
  output=$("$PW_METADATA" -n settings 0 clock.force-quantum)
  if [[ "$output" =~ value:\'([0-9]+)\' ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    echo "Cannot read force-quantum (refusing to change global audio settings): $output" >&2
    return 1
  fi
}
case "${1:-}" in
  status)
    "$PW_METADATA" -n settings 0
    ;;
  restore)
    if [[ "$(read_force)" != 0 ]]; then
      echo 'Restoring PipeWire graph clock.force-quantum=0' >&2
      "$PW_METADATA" -n settings 0 clock.force-quantum 0
    fi
    ;;
  run)
    q=${2:-}
    case "$q" in 256|128|64|32) ;; *) help >&2; exit 2;; esac
    [[ "${3:-}" == '--' && $# -ge 4 ]] || { help >&2; exit 2; }
    shift 3
    # Lock serializes experiments; this cannot protect against other apps changing metadata.
    runtime=${XDG_RUNTIME_DIR:-/tmp}
    [[ -d "$runtime" ]] || { echo 'XDG_RUNTIME_DIR missing' >&2; exit 1; }
    lock="$runtime/osu-audio-quantum-lab-${UID}.lock"
    exec 9>"$lock"
    "$FLOCK" -n 9 || { echo 'Another audio quantum experiment is active' >&2; exit 1; }
    before=$(read_force)
    [[ "$before" == 0 ]] || { echo "Existing forced quantum is $before; refusing to overwrite" >&2; exit 1; }
    changed=0
    cleanup() {
      local exit_status=$?
      trap - EXIT INT TERM HUP
      if ((changed)); then
        # Do not overwrite a quantum value that another client changed meanwhile.
        local now
        now=$(read_force) || { echo 'ERROR: could not verify quantum; run restore after checking other apps' >&2; exit 1; }
        if [[ "$now" == "$q" ]]; then
          if ! "$PW_METADATA" -n settings 0 clock.force-quantum 0 >&2; then
            echo 'ERROR: restore failed; run osu-audio-quantum-lab restore' >&2
            exit 1
          fi
        else
          echo "WARN: force-quantum changed externally ($now); preserving external value" >&2
        fi
      fi
      exit "$exit_status"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    changed=1
    "$PW_METADATA" -n settings 0 clock.force-quantum "$q"
    actual=$(read_force)
    [[ "$actual" == "$q" ]] || { echo "Requested $q but metadata reports $actual" >&2; exit 1; }
    printf 'Temporary graph quantum: %s frames (at 48000Hz: %d.%03d ms). Close COMMAND to restore.\n' "$q" "$((q * 1000 / 48000))" "$((q * 1000000 / 48000 % 1000))"
    "$@"
    ;;
  -h|--help|help|'') help;;
  *) help >&2; exit 2;;
esac
