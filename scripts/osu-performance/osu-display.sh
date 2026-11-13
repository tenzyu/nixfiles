#!/usr/bin/env bash
# Opt-in, reversible Hyprland v0.57.x tearing experiment.
# No game binary/SDL modification, KMS writes, global cursor changes or sudo.
set -Eeuo pipefail

RULE='neko5-osu-display-tearing'
MONITOR='eDP-1'
TIMEOUT_SECONDS=3

usage() {
  cat <<'USAGE'
usage: osu-display {status|try [1..60]|on|off}
  status   print current osu!/monitor/rule state (no changes)
  try 12   permit tearing for at most 12s, then restore rule OFF
  on       enable without timeout, only after a verified successful try
  off      disable this named tearing rule, also from another terminal
Notes:
  Start the trial with osu! foreground and 2/0 Direct Scanout working.
  A visible cursor, a screen overlay, or an unsupported DRM backend may block tearing.
  OFF does not require game focus and never changes the game's fullscreen state.
  If the compositor hangs, use another TTY or boot the earlier NixOS generation.
USAGE
}

ipc() { timeout -k 1s "${TIMEOUT_SECONDS}s" hyprctl "$@"; }
monitor_json() {
  ipc -j monitors | jq -ec --arg name "$MONITOR" '[.[] | select(.name == $name)] | first // empty'
}
window_json() { ipc -j activewindow; }

# Hyprland 0.57.2 has getprop, eval and named Lua rules, not "hyprctl setprop".
# Use an identifiable, default-disabled named rule, never a global immediate rule.
rule() {
  local state="$1" script response
  case "$state" in true|false) :;; *) return 64;; esac
  script="hl.window_rule({ name = \"$RULE\", match = { class = \"^(osu!|osu-lazer)$\" }, immediate = true, enabled = $state })"
  response="$(ipc eval "$script")" || { printf 'Hyprland eval failed: %s\n' "$response" >&2; return 1; }
  case "$response" in *error*|*Error*) printf 'Hyprland rejected Lua rule: %s\n' "$response" >&2; return 1;; esac
}

state() {
  local win mon
  win="$(window_json)" || { echo 'Cannot read Hyprland activewindow IPC' >&2; return 1; }
  mon="$(monitor_json)" || { echo "Monitor $MONITOR not found" >&2; return 1; }
  jq -nc --argjson window "$win" --argjson monitor "$mon" '{window:$window,monitor:$monitor}'
}

# This predicate reproduces the user's actually measured 2/0 + DSO path.
# directScanoutTo is compositor state, not a physical async-flip counter.
ready() {
  jq -e --arg mon "$MONITOR" '
    (.window.class == "osu!" or .window.class == "osu-lazer") and
    .window.fullscreen == 2 and .window.fullscreenClient == 0 and
    .window.xwayland == false and
    .monitor.name == $mon and
    ((.monitor.directScanoutTo // "0" | tostring) != "0") and
    ((.monitor.directScanoutBlockedBy // []) | length == 0)
  ' >/dev/null
}

check_master() {
  local option
  option="$(ipc -j getoption general:allow_tearing)" || return 1
  jq -e '.bool == true or .int == 1' >/dev/null <<< "$option"
}

prop_enabled() {
  local win addr response
  win="$(window_json)" || return 1
  addr="$(jq -r '.address // ""' <<< "$win")"
  [[ "$addr" =~ ^(0x)?[0-9a-fA-F]+$ ]] || { echo 'Missing activewindow address for getprop' >&2; return 1; }
  response="$(ipc -j getprop "address:$addr" immediate)" || return 1
  jq -e '.immediate == true or .immediate == 1' >/dev/null <<< "$response"
}

wait_for_enabled() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    if prop_enabled; then return 0; fi
    sleep 0.2
  done
  return 1
}

print_status() {
  local current prop='unknown'
  current="$(state)" || return 1
  if prop_enabled; then prop='enabled'; else prop='disabled_or_unavailable'; fi
  jq -r --arg prop "$prop" '
    "active=\(.window.class // "none") fs=\(.window.fullscreen // "?")/\(.window.fullscreenClient // "?") xwayland=\(.window.xwayland // "?")",
    "monitor=\(.monitor.name) @\(.monitor.refreshRate // "?")Hz directScanoutTo=\(.monitor.directScanoutTo // "0") blockedBy=\((.monitor.directScanoutBlockedBy // [])|join(","))",
    "activelyTearing=\(.monitor.activelyTearing // false) tearingHint=\(.window.tearingHint // false) tearingBlockedBy=\((.monitor.tearingBlockedBy // [])|join(","))",
    "named_rule=" + $prop
  ' <<< "$current"
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -f "$XDG_RUNTIME_DIR/neko5-osu-display/last-trial.txt" ]]; then
    printf 'last_trial: '
    cat -- "$XDG_RUNTIME_DIR/neko5-osu-display/last-trial.txt"
  fi
}

preflight() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || { echo 'HYPRLAND_INSTANCE_SIGNATURE missing: run inside your Hyprland session' >&2; return 2; }
  command -v hyprctl >/dev/null || { echo 'hyprctl missing' >&2; return 2; }
  command -v jq >/dev/null || { echo 'jq missing' >&2; return 2; }
  check_master || { echo 'general:allow_tearing is disabled/unreadable' >&2; return 2; }
  state | ready || { echo 'Not in foreground osu! 2/0 + eDP Direct Scanout state: refusing test' >&2; print_status >&2 || :; return 2; }
}

runtime_root() {
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || { echo 'XDG_RUNTIME_DIR missing' >&2; return 2; }
  printf '%s/neko5-osu-display\n' "$XDG_RUNTIME_DIR"
}

# Session-specific gate. A separate, successful trial is required before "on".
marker_path() {
  local root
  root="$(runtime_root)" || return
  [[ "${HYPRLAND_INSTANCE_SIGNATURE:-}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'Invalid Hyprland instance signature' >&2; return 2; }
  printf '%s/verified-%s\n' "$root" "$HYPRLAND_INSTANCE_SIGNATURE"
}

try_temporary() {
  local seconds="$1" marker root sample count=0
  [[ "$seconds" =~ ^[0-9]{1,2}$ ]] && (( seconds>=1 && seconds<=60 )) || { echo 'try duration must be 1..60 seconds' >&2; return 64; }
  preflight || return $?
  marker="$(marker_path)" || return 2
  root="$(dirname "$marker")"
  mkdir -m 700 -p -- "$root"
  umask 077
  # Do not allow two independent trial watchdogs to race.
  exec 9> "$root/trial.lock"
  flock -n 9 || { echo 'Another osu-display trial is running' >&2; return 2; }
  rm -f -- "$marker"
  printf 'RUNNING %ss (recheck after completion)\n' "$seconds" > "$root/last-trial.txt"
  # Any early exit, error, Ctrl+C or SIGTERM must turn tearing OFF.
  trap 'rule false || echo "WARNING: tearing rule could not be restored; use osu-display off or reload Hyprland" >&2' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  rule true
  wait_for_enabled || { echo 'Named rule was not observed as enabled; refusing test' >&2; return 3; }
  printf 'Trial enabled for at most %ss; keeping osu! foreground.\n' "$seconds" >&2
  for ((i=1;i<=seconds;i++)); do
    sleep 1
    sample="$(state)" || return 3
    if ! ready <<< "$sample"; then
      echo 'Direct Scanout/foreground/fullscreen geometry lost; reverting' >&2
      printf 'ABORTED: DSO or 2/0 lost at second %d/%d\n' "$i" "$seconds" > "$root/last-trial.txt"
      return 3
    fi
    if jq -e '.monitor.activelyTearing == true' >/dev/null <<< "$sample"; then
      count=$((count + 1))
    fi
  done
  # The trial ends with a rollback even if the compositor reported tearing.
  rule false
  trap - EXIT INT TERM HUP
  printf 'Trial ended. activelyTearing-positive samples=%d/%d (1 Hz).\n' "$count" "$seconds" >&2
  if (( count < 2 )); then
    echo 'No sustained tearing state observed; persistent mode NOT unlocked' >&2
    printf 'INCONCLUSIVE: tearing-positive=%d/%d; rule reset OFF\n' "$count" "$seconds" > "$root/last-trial.txt"
    return 4
  fi
  printf 'compositor=%s\nobserved_tearing_samples=%s\n' "$HYPRLAND_INSTANCE_SIGNATURE" "$count" > "$marker"
  printf 'PASSED: tearing-positive=%d/%d; rule reset OFF; not optical proof\n' "$count" "$seconds" > "$root/last-trial.txt"
  echo 'Persistent-mode gate unlocked for this Hyprland instance; physical flip latency is still unmeasured.' >&2
}

on_persistent() {
  local marker
  preflight || return $?
  marker="$(marker_path)" || return 2
  [[ -f "$marker" ]] || { echo 'Run `osu-display try 12` successfully before persistent mode' >&2; return 2; }
  rule true
  wait_for_enabled || { rule false || :; echo 'Named rule did not become active' >&2; return 3; }
  echo 'Tearing requested until `osu-display off` or compositor reload. No optical latency gain is proven.' >&2
}

command="${1:-}"
case "$command" in
  status) [[ $# -eq 1 ]] || { usage >&2; exit 64; }; print_status ;;
  try) [[ $# -le 2 ]] || { usage >&2; exit 64; }; try_temporary "${2:-12}" ;;
  on) [[ $# -eq 1 ]] || { usage >&2; exit 64; }; on_persistent ;;
  off) [[ $# -eq 1 ]] || { usage >&2; exit 64; }; rule false; echo 'Named tearing rule disabled; no monitor or game settings changed' ;;
  *) usage >&2; exit 64 ;;
esac
