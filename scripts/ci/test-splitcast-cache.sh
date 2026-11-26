#!/usr/bin/env bash
set -euo pipefail
script=$1
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cd "$scratch"
mkdir bin
export PATH="$PWD/bin:$PATH" GITHUB_STEP_SUMMARY="$PWD/summary"
printf '%s\n' '{"nodes":{"splitcast":{"locked":{"rev":"fixture"}}}}' > flake.lock
cat > bin/nix <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  eval)
    case "$*" in
      *extra-substituters*) echo '["https://github.com/tenzyu/splitcast/releases/download/nix-cache-fixture"]' ;;
      *extra-trusted-public-keys*) echo '["splitcast-1:fixture"]' ;;
      *) echo /nix/store/fixture ;;
    esac ;;
  path-info) exit 0 ;;
  copy) exit "${COPY_STATUS:-0}" ;;
  *) exit 99 ;;
esac
MOCK
# Use the actual Bash path in a Nix sandbox.
sed -i "1c#!$(command -v bash)" bin/nix
chmod +x bin/nix
rc=0
bash "$script" --help extra > /dev/null 2>&1 || rc=$?
test "$rc" = 2
rc=0
COPY_STATUS=1 bash "$script" --strict > failed.log 2>&1 || rc=$?
test "$rc" = 1
grep -F 'Strict signed-copy verification failed for 3 output(s).' "$GITHUB_STEP_SUMMARY"
if grep -Fq 'SIGNED-COPY-OK: Nix accepted' "$GITHUB_STEP_SUMMARY"; then exit 1; fi
: > "$GITHUB_STEP_SUMMARY"
bash "$script" --strict > passed.log 2>&1
grep -F 'SIGNED-COPY-OK: Nix accepted' "$GITHUB_STEP_SUMMARY"
