#!/usr/bin/env bash
set -euo pipefail
launch="$1"
sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox"' EXIT
mkdir -p "$sandbox/bin"
cat >"$sandbox/bin/gamemoderun" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat >"$sandbox/bin/gamescope" <<'EOF'
#!/usr/bin/env bash
printf 'game:%s\n' "$*" >> "$TEST_LOG"
if [[ "$GAME_MODE" == "slow" ]]; then exec sleep 20; fi
exit "$GAME_EXIT"
EOF
cat >"$sandbox/bin/hypr-gaming-mode" <<'EOF'
#!/usr/bin/env bash
printf 'mode:%s\n' "$1" >> "$TEST_LOG"
if [[ "$1" == "on" && "$ON_FAIL" == 1 ]]; then exit 12; fi
EOF
# Nix build sandboxes do not provide /usr/bin/env or /bin/sh.
# Replace fixture shebangs with the Bash executable in this derivation.
for mock in "$sandbox/bin/"*; do
  {
    printf '#!%s\n' "$(command -v bash)"
    tail -n +2 "$mock"
  } > "$mock.fixed"
  mv "$mock.fixed" "$mock"
done
chmod +x "$sandbox/bin/"*
export PATH="$sandbox/bin:$PATH"
export TEST_LOG="$sandbox/log"
export GAME_MODE=normal GAME_EXIT=0 ON_FAIL=0

: > "$TEST_LOG"
bash "$launch" marker
[[ "$(grep -c '^mode:on$' "$TEST_LOG")" == 1 ]]
[[ "$(grep -c '^mode:off$' "$TEST_LOG")" == 1 ]]
grep -Fq 'game:--backend sdl --steam --rt -f -W 1366 -H 768 -r 60 -- steam marker' "$TEST_LOG"

: > "$TEST_LOG"
GAME_EXIT=17 bash "$launch" marker && { echo "child failure was suppressed" >&2; exit 1; } || rc="$?"
[[ "$rc" == 17 ]]
[[ "$(grep -c '^mode:off$' "$TEST_LOG")" == 1 ]]

: > "$TEST_LOG"
ON_FAIL=1 bash "$launch" marker
grep -Fqx 'mode:on' "$TEST_LOG"
! grep -Fqx 'mode:off' "$TEST_LOG"

: > "$TEST_LOG"
GAME_MODE=slow bash "$launch" marker &
launcher="$!"
ready=0
for _ in {1..100}; do
  if grep -Fq 'game:' "$TEST_LOG"; then ready=1; break; fi
  sleep 0.05
done
[[ "$ready" == 1 ]] || { echo "game did not start" >&2; kill -TERM "$launcher" || true; exit 1; }
kill -TERM "$launcher"
rc=0
wait "$launcher" || rc="$?"
[[ "$rc" == 143 ]]
[[ "$(grep -c '^mode:off$' "$TEST_LOG")" == 1 ]]
echo "steam-gaming cleanup, failure and SIGTERM: PASS"
