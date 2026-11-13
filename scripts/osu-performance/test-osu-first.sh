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
exit 1
MOCK
cat > "$root/bin/pgrep" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$root/bin/"*
export PATH="$root/bin:$PATH" TEST_LAUNCH_LOG="$root/launch.log" TEST_SCOPE_LOG="$root/scope.log"
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
# Check the real prctl entrypoint, but never launch osu!.
python3 "$script_dir/timerslack-exec.py" --nanoseconds 1000 --best-effort -- true
printf '%s\n' 'PASS: 11 launcher scenarios + timer helper'
