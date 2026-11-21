#!/usr/bin/env bash
# Hermetic launcher regression tests; no real osu!, PipeWire or systemd changes.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin"
cat > "$root/bin/osu-lazer" <<'MOCK'
#!/usr/bin/env bash
printf 'launch %s\n' "$*" >> "$TEST_LAUNCH_LOG"
exit "${TEST_GAME_RC:-0}"
MOCK
cat > "$root/bin/systemd-run" <<'MOCK'
#!/usr/bin/env bash
if [[ ${TEST_SCOPE_FAIL:-0} == 1 ]]; then exit 73; fi
printf '%s\n' "$*" >> "$TEST_SCOPE_LOG"
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
shift
"$@"
MOCK
cat > "$root/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
if [[ "$*" == '--user is-active --quiet mako.service' ]]; then
  exit "${TEST_MAKO_SERVICE_RC:-0}"
fi
exit 1
MOCK
cat > "$root/bin/makoctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_MAKO_LOG"
if [[ "$*" == mode ]]; then
  if [[ ${TEST_MAKO_READ_RC:-0} != 0 ]]; then exit "$TEST_MAKO_READ_RC"; fi
  printf '%s\n' default
  if [[ ${TEST_MAKO_PREEXISTING:-0} == 1 ]]; then printf '%s\n' osu-first; fi
  exit 0
fi
exit "${TEST_MAKO_CHANGE_RC:-0}"
MOCK
cat > "$root/bin/pgrep" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$root/bin/"*
export PATH="$root/bin:$PATH" TEST_LAUNCH_LOG="$root/launch.log" TEST_SCOPE_LOG="$root/scope.log"
export TEST_MAKO_LOG="$root/mako.log" TEST_SYSTEMCTL_LOG="$root/systemctl.log"
export OSU_FIRST_SUPPRESS_UI=0 OSU_FIRST_TIMER_MODE=off
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_count() { local lines=0; [[ ! -f "$TEST_LAUNCH_LOG" ]] || lines="$(wc -l < "$TEST_LAUNCH_LOG")"; [[ "$lines" == "$1" ]] || fail "expected $1 launches, got $lines"; }
reset() { rm -f "$TEST_LAUNCH_LOG"; }
reset
OSU_FIRST_SCOPE_MODE=auto "$script_dir/osu-first.sh" solo -- --test >/dev/null
expect_count 1
grep -q -- '--property=CPUWeight=500' "$TEST_SCOPE_LOG" || fail 'scope weight must be 500'
grep -q -- '--property=CPUUClampMin=0%' "$TEST_SCOPE_LOG" || fail 'scope clamp default must be 0'
reset
TEST_SCOPE_FAIL=1 OSU_FIRST_SCOPE_MODE=auto "$script_dir/osu-first.sh" solo >/dev/null
expect_count 1
reset
if TEST_SCOPE_FAIL=1 OSU_FIRST_SCOPE_MODE=required "$script_dir/osu-first.sh" solo >/dev/null 2>&1; then fail 'required scope should fail'; fi
expect_count 0
reset
if TEST_GAME_RC=7 OSU_FIRST_SCOPE_MODE=auto "$script_dir/osu-first.sh" solo >/dev/null 2>&1; then fail 'game exit 7 should propagate'; else rc=$?; fi
[[ "$rc" == 7 ]] || fail "expected game status 7 got $rc"
expect_count 1
reset
OSU_FIRST_SCOPE_MODE=off "$script_dir/osu-first.sh" solo >/dev/null
expect_count 1
reset
if OSU_FIRST_BASS_PERIOD=-64 "$script_dir/osu-first.sh" solo >/dev/null 2>&1; then fail 'BASS -64 should be rejected'; fi
expect_count 0
reset
OSU_FIRST_SCOPE_MODE=off OSU_FIRST_TIMER_MODE=auto OSU_FIRST_TIMER_EXEC=/does/not/exist "$script_dir/osu-first.sh" solo >/dev/null
expect_count 1
reset
if OSU_FIRST_SCOPE_MODE=off OSU_FIRST_TIMER_MODE=required OSU_FIRST_TIMER_EXEC=/does/not/exist "$script_dir/osu-first.sh" solo >/dev/null 2>&1; then fail 'missing required timer helper should fail'; fi
expect_count 0
reset
OSU_FIRST_SCOPE_MODE=auto "$script_dir/osu-first.sh" doctor >/dev/null
expect_count 0
reset
if OSU_FIRST_CPU_WEIGHT=0 "$script_dir/osu-first.sh" solo >/dev/null 2>&1; then fail 'zero CPU weight should fail'; fi
expect_count 0
reset
if OSU_FIRST_CPU_WEIGHT=10001 "$script_dir/osu-first.sh" solo >/dev/null 2>&1; then fail 'out-of-range CPU weight should fail'; fi
expect_count 0
# Mako mode ownership must not stop/start units or D-Bus-activate inactive Mako.
expected_mako_log="$(printf '%s\n' 'mode' 'mode -a osu-first' 'mode -r osu-first')"
expected_systemctl_log='--user is-active --quiet mako.service'
expect_only_readonly_systemctl() {
  [[ "$(cat "$TEST_SYSTEMCTL_LOG")" == "$expected_systemctl_log" ]] || fail 'Mako unit must only be queried, never stopped or started'
}
reset
rm -f "$TEST_MAKO_LOG" "$TEST_SYSTEMCTL_LOG"
OSU_FIRST_SUPPRESS_UI=1 OSU_FIRST_SCOPE_MODE=off "$script_dir/osu-first.sh" solo >/dev/null
expect_count 1
[[ "$(cat "$TEST_MAKO_LOG")" == "$expected_mako_log" ]] || fail 'Mako mode must be enabled and restored'
expect_only_readonly_systemctl
# Restore notifications even when the game exits with an error.
reset
rm -f "$TEST_MAKO_LOG" "$TEST_SYSTEMCTL_LOG"
if TEST_GAME_RC=7 OSU_FIRST_SUPPRESS_UI=1 OSU_FIRST_SCOPE_MODE=off "$script_dir/osu-first.sh" solo >/dev/null 2>&1; then fail 'game exit 7 must propagate'; else rc=$?; fi
[[ "$rc" == 7 ]] || fail "expected game status 7 got $rc"
expect_count 1
[[ "$(cat "$TEST_MAKO_LOG")" == "$expected_mako_log" ]] || fail 'Mako mode must be restored after game failure'
expect_only_readonly_systemctl
# If adding a mode fails, the launcher may not remove a mode it never added.
reset
rm -f "$TEST_MAKO_LOG" "$TEST_SYSTEMCTL_LOG"
TEST_MAKO_CHANGE_RC=71 OSU_FIRST_SUPPRESS_UI=1 OSU_FIRST_SCOPE_MODE=off "$script_dir/osu-first.sh" solo >/dev/null 2>&1
expect_count 1
[[ "$(cat "$TEST_MAKO_LOG")" == "$(printf '%s\n' mode 'mode -a osu-first')" ]] || fail 'failed mode activation must not trigger removal'
expect_only_readonly_systemctl
# An inactive unit must NOT be D-Bus-activated by makoctl mode.
reset
rm -f "$TEST_MAKO_LOG" "$TEST_SYSTEMCTL_LOG"
TEST_MAKO_SERVICE_RC=3 OSU_FIRST_SUPPRESS_UI=1 OSU_FIRST_SCOPE_MODE=off "$script_dir/osu-first.sh" solo >/dev/null 2>&1
expect_count 1
[[ ! -e "$TEST_MAKO_LOG" ]] || fail 'inactive Mako must not receive a D-Bus call'
expect_only_readonly_systemctl
# Do not remove an invisible mode which was already active before osu-first.
reset
rm -f "$TEST_MAKO_LOG" "$TEST_SYSTEMCTL_LOG"
TEST_MAKO_PREEXISTING=1 OSU_FIRST_SUPPRESS_UI=1 OSU_FIRST_SCOPE_MODE=off "$script_dir/osu-first.sh" solo >/dev/null
expect_count 1
[[ "$(cat "$TEST_MAKO_LOG")" == mode ]] || fail 'pre-existing Mako mode must be untouched'
expect_only_readonly_systemctl
# A failed mode read must not be followed by an ambiguous state-changing call.
reset
rm -f "$TEST_MAKO_LOG" "$TEST_SYSTEMCTL_LOG"
TEST_MAKO_READ_RC=72 OSU_FIRST_SUPPRESS_UI=1 OSU_FIRST_SCOPE_MODE=off "$script_dir/osu-first.sh" solo >/dev/null 2>&1
expect_count 1
[[ "$(cat "$TEST_MAKO_LOG")" == mode ]] || fail 'failed Mako read must not mutate modes'
expect_only_readonly_systemctl
# Check the real prctl entrypoint, but never launch osu!.
python3 "$script_dir/timerslack-exec.py" --nanoseconds 1000 --best-effort -- true
printf '%s\n' 'PASS: 17 launcher scenarios + timer helper'
