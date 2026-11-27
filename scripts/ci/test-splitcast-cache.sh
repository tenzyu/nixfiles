#!/usr/bin/env bash
set -euo pipefail
script=$1
scratch=$(mktemp -d)
trap 'find "$scratch" -type d -exec chmod u+w {} +; rm -rf -- "$scratch"' EXIT
cd "$scratch"
mkdir bin tmp
export TMPDIR="$PWD/tmp" MOCK_STORE_ROOT_FILE="$PWD/mock-store-root"
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
  copy)
    grep -Fxq 'require-sigs = true' <<< "${NIX_CONFIG:-}" || exit 98
    grep -Fxq 'trusted-public-keys = splitcast-1:fixture cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=' <<< "${NIX_CONFIG:-}" || exit 98
    root=
    for arg in "$@"; do
      case "$arg" in
        local\?root=*) root="${arg#local\?root=}" ;;
      esac
    done
    test -n "$root" || exit 97
    printf '%s\n' "$root" > "$MOCK_STORE_ROOT_FILE"
    if [[ ! -d "$root/nix/store/mock-output" ]]; then
      mkdir -p "$root/nix/store/mock-output/subdir"
      touch "$root/nix/store/mock-output/subdir/file"
      chmod a-w "$root/nix/store/mock-output/subdir" "$root/nix/store/mock-output"
    fi
    exit "${COPY_STATUS:-0}" ;;
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
test ! -e "$(cat "$MOCK_STORE_ROOT_FILE")"
: > "$GITHUB_STEP_SUMMARY"
bash "$script" --strict > passed.log 2>&1
grep -F 'SIGNED-COPY-OK: Nix accepted' "$GITHUB_STEP_SUMMARY"
test ! -e "$(cat "$MOCK_STORE_ROOT_FILE")"
