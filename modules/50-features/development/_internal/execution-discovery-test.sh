#!/usr/bin/env bash
set -euo pipefail
script=${1:?path to execution-discovery.sh required}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PATH="$work:$PATH"
printf '#!%s\n' "$(command -v bash)" > "$work/incus"
cat >> "$work/incus" <<'MOCK'
case "$*" in
  'query lab:/1.0?project=lab')
    case "$CASE" in
      untrusted) auth=untrusted; project=lab; clustered=false ;;
      wrong-project) auth=trusted; project=default; clustered=false ;;
      clustered) auth=trusted; project=lab; clustered=true ;;
      malformed) echo '{'; exit 0 ;;
      *) auth=trusted; project=lab; clustered=false ;;
    esac
    printf '{"auth":"%s","environment":{"project":"%s","server_clustered":%s,"driver":"lxc | qemu"}}\n' "$auth" "$project" "$clustered"
    if [[ $CASE == query-fails ]]; then exit 42; fi
    ;;
  'list lab: --format=json')
    echo '[]'
    if [[ $CASE == list-fails ]]; then exit 42; fi
    ;;
  *) exit 99 ;;
esac
MOCK
printf '#!%s\n' "$(command -v bash)" > "$work/docker"
cat >> "$work/docker" <<'MOCK'
[[ $* == "info --format {{json .SecurityOptions}}" ]] || exit 99
case "$CASE" in
  docker-lookalike) echo '["name=rootless-other"]' ;;
  docker-malformed) echo '{' ;;
  *) echo '["name=seccomp,profile=builtin","name=rootless"]' ;;
esac
if [[ $CASE == docker-fails ]]; then exit 42; fi
MOCK
printf '#!%s\n' "$(command -v bash)" > "$work/systemctl"
cat >> "$work/systemctl" <<'MOCK'
[[ $* == '--user show-environment' && $CASE != systemd-fails ]]
MOCK
printf '#!%s\n' "$(command -v bash)" > "$work/nix"
cat >> "$work/nix" <<'MOCK'
[[ $* == 'store ping' && $CASE != nix-fails ]]
MOCK
chmod +x "$work"/*
failures=0
check() {
  local scenario=$1 predicate=$2 actual
  if ! actual=$(CASE="$scenario" bash "$script"); then
    printf 'FAIL %s: probe command failed\n' "$scenario" >&2
    failures=$((failures + 1))
    return
  fi
  if ! jq -e "$predicate" <<< "$actual" >/dev/null; then
    printf 'FAIL %s: %s\n' "$scenario" "$(jq -c . <<< "$actual")" >&2
    failures=$((failures + 1))
    return
  fi
  printf 'PASS %s\n' "$scenario"
}
check positive '.user_systemd and .nix_store and .rootless_docker and .incus.lab_authenticated and .incus.advertised_drivers == ["lxc","qemu"]'
for scenario in query-fails list-fails untrusted wrong-project clustered malformed; do
  check "$scenario" '(.incus.lab_authenticated | not) and .incus.advertised_drivers == []'
done
for scenario in docker-fails docker-lookalike docker-malformed; do
  check "$scenario" '.rootless_docker | not'
done
check systemd-fails '.user_systemd | not'
check nix-fails '.nix_store | not'
test "$failures" -eq 0
