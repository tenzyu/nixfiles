#!/usr/bin/env bash
# Hermetic IPC tests: no NixOS, real Wayland, i915 or osu! process required.
set -Eeuo pipefail
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/runtime"
cat > "$root/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
statefile="$TEST_ROOT/rule_state"
logfile="$TEST_ROOT/rule_log"
enabled=false
if [[ -e "$statefile" ]] && [[ "$(cat "$statefile")" == true ]]; then enabled=true; fi
case "$*" in
  'eval '*)
    [[ "$*" == *'name = "neko5-osu-display-tearing"'* && "$*" == *'immediate = true'* ]] || { echo 'error: bad lua code'; exit 1; }
    if [[ "$*" == *'enabled = true'* ]]; then enabled=true; else enabled=false; fi
    echo "$enabled" > "$statefile"
    echo "$enabled" >> "$logfile"
    echo ok
    ;;
  '-j activewindow')
    printf '{"class":"%s","address":"5ae61c02c5d0","fullscreen":%s,"fullscreenClient":%s,"xwayland":false,"tearingHint":false}\n' "${TEST_CLASS:-osu!}" "${TEST_CLIENT_FS:-2}" "${TEST_CLIENT_FS_CLIENT:-0}"
    ;;
  '-j monitors')
    dso='5ae61c02c5d0'
    [[ "${TEST_NO_DSO:-0}" != 1 ]] || dso=0
    if [[ "$enabled" == true && "${TEST_DSO_DROPS:-0}" == 1 ]];then dso=0;fi
    tear=false
    if [[ "$enabled" == true && "${TEST_CAN_TEAR:-1}" == 1 ]];then tear=true;fi
    if [[ "$dso" == 0 ]];then block='["TRANSFORM"]';else block='[]';fi
    printf '[{"name":"eDP-1","refreshRate":60.003,"directScanoutTo":"%s","directScanoutBlockedBy":%s,"activelyTearing":%s,"tearingBlockedBy":[]}]\n' "$dso" "$block" "$tear"
    ;;
  '-j getoption general:allow_tearing')
    if [[ "${TEST_MASTER_OFF:-0}" == 1 ]];then echo '{"bool":false}';else echo '{"bool":true}';fi
    ;;
  '-j getprop '*immediate)
    echo "{\"immediate\":$enabled}"
    ;;
  *) echo "unknown test command: $*" >&2; exit 3;;
esac
MOCK
cat > "$root/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$root/bin/"*
export TEST_ROOT="$root" XDG_RUNTIME_DIR="$root/runtime" HYPRLAND_INSTANCE_SIGNATURE="test-session-20261113"
export PATH="$root/bin:$PATH"
script="$(cd "$(dirname "$0")" && pwd)/osu-display.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
reset() { rm -f -- "$root/rule_state" "$root/rule_log"; rm -rf -- "$root/runtime/neko5-osu-display"; }
# Read-only status, prior to any modifications.
reset
bash "$script" status > "$root/status.txt"
[[ ! -e "$root/rule_log" ]] || fail 'status changed the rule'
grep -q 'directScanoutTo=5ae' "$root/status.txt" || fail 'status failed to show DSO'
# Refuse to enable tearing if the known-good geometry or DSO is absent.
reset
if TEST_CLIENT_FS_CLIENT=2 bash "$script" try 2 > /dev/null 2>&1; then fail '2/2 should refuse'; fi
[[ ! -e "$root/rule_log" ]] || fail '2/2 toggled rule'
reset
if TEST_NO_DSO=1 bash "$script" try 2 > /dev/null 2>&1; then fail 'no DSO should refuse'; fi
[[ ! -e "$root/rule_log" ]] || fail 'no DSO toggled rule'
reset
if TEST_MASTER_OFF=1 bash "$script" try 2 > /dev/null 2>&1; then fail 'master off should refuse'; fi
[[ ! -e "$root/rule_log" ]] || fail 'master off toggled rule'
# Trial must restore OFF and gate persistent enable on two positive samples.
reset
bash "$script" try 2 > /dev/null
[[ "$(cat "$root/rule_state")" == false ]] || fail 'trial did not disable rule'
grep -q '^PASSED:' "$root/runtime/neko5-osu-display/last-trial.txt" || fail 'trial result unavailable to users'
[[ "$(tr '\n' ' ' < "$root/rule_log")" == 'true false ' ]] || fail 'unexpected rule transitions in successful try'
[[ -f "$root/runtime/neko5-osu-display/verified-$HYPRLAND_INSTANCE_SIGNATURE" ]] || fail 'no verification gate'
bash "$script" on > /dev/null
[[ "$(cat "$root/rule_state")" == true ]] || fail 'persistent on did not enable'
bash "$script" off > /dev/null
[[ "$(cat "$root/rule_state")" == false ]] || fail 'manual off did not disable'
# With no observed tearing, the script must turn off, refuse gate.
reset
if TEST_CAN_TEAR=0 bash "$script" try 2 > /dev/null 2>&1; then fail 'no tearing reported success'; fi
[[ "$(cat "$root/rule_state")" == false ]] || fail 'failed trial did not disable'
grep -q '^INCONCLUSIVE:' "$root/runtime/neko5-osu-display/last-trial.txt" || fail 'missing failed trial result'
if bash "$script" on > /dev/null 2>&1; then fail 'persistent on accepted failed trial'; fi
# If the driver cannot retain DSO, abort immediately and disable.
reset
if TEST_DSO_DROPS=1 bash "$script" try 2 > /dev/null 2>&1; then fail 'DSO regression not detected'; fi
[[ "$(cat "$root/rule_state")" == false ]] || fail 'DSO regression left rule enabled'
grep -q '^ABORTED:' "$root/runtime/neko5-osu-display/last-trial.txt" || fail 'missing abort reason'
# Off works without osu foreground.
reset
TEST_CLASS=kitty bash "$script" off > /dev/null
[[ "$(cat "$root/rule_state")" == false ]] || fail 'off required game focus'
echo 'PASS: status + 2/2 rejection + DSO rejection + master rejection + trial rollback + gated persistent on + manual off + no-tearing + DSO regression + unfocused off'
