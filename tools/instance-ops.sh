#!/usr/bin/env bash
# Native Incus/Nix own state. Only compound-operation admission and sequencing
# belong here. Internal artifact commands are shared by production and CI.
set -euo pipefail

die() { printf '%s\n' "$1" >&2; exit "${2:-1}"; }
valid_name() { [[ $1 =~ ^[a-z][a-z0-9-]{0,62}$ ]]; }
valid_workload() { [[ $1 =~ ^[a-z][a-z0-9-]*$ ]]; }
inc() { sudo incus "$@"; }
get() { inc config get "local:$1" "$2" --project default; }

# Explicit guest environment; the agent does not start a NixOS login shell.
guest_options=(--project default --mode=non-interactive --cwd / --env PATH=/run/wrappers/bin:/run/current-system/sw/bin)
guest_stream() {
  local name=$1; shift
  inc exec "local:$name" "${guest_options[@]}" -- "$@"
}
guest() { guest_stream "$@" </dev/null; }

# Subshell bounds the FD and umask to the operation, including on failure.
with_lock() (
  local name=$1; shift
  valid_name "$name" || die "Invalid instance name: $name" 2
  umask 007
  exec 9>"/run/lock/neko7-instances/$name.lock"
  flock -n 9 || die "Instance operation already running: $name"
  umask 077
  "$@"
)

managed_identity() {
  local workload uuid
  workload=$(get "$1" user.nixfiles.workload)
  uuid=$(get "$1" volatile.uuid)
  valid_workload "$workload" && [[ -n $uuid ]] || die "Not a managed workload: $1"
  printf '%s\n%s\n' "$workload" "$uuid"
}

ready() {
  local name=$1 budget=${NEKO7_READINESS_TIMEOUT:-300}
  [[ $budget =~ ^[1-9][0-9]{0,3}$ ]] && (( budget <= 900 )) ||
    die "Invalid readiness budget (1..900 seconds)" 2
  local deadline=$((SECONDS + budget)) remaining probe
  while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    probe=$((remaining < 30 ? remaining : 30))
    if timeout -k 5s "${probe}s" sudo incus exec "local:$name" "${guest_options[@]}" -- /etc/neko7/readiness </dev/null; then
      return 0
    fi
    if (( SECONDS + 2 < deadline )); then sleep 2; else break; fi
  done
  die "Readiness failed after bounded wait; inspect local:$name, do not automatically roll back data"
}

bundle() {
  local name=$1 dest=$2 workload=$3 uuid=$4 parent mode status
  [[ $dest == /* ]] || die "Backup destination must be absolute" 2
  # mkdir is atomic no-overwrite admission. A partial bundle is invalid.
  parent=$(dirname "$dest")
  sudo test -d "$parent"
  mode=$(sudo stat -Lc %a "$parent")
  (( (8#$mode & 077) == 0 )) || die "Backup parent must be private (0700)"
  sudo mkdir -m 0700 -- "$dest"
  status=$(inc list local: --project default --format json | jq -er --arg name "$name" '.[] | select(.name == $name) | .status')
  case "$status" in
    Running) inc stop "local:$name" --project default ;;
    Stopped) ;;
    *) die "Unexpected status: $status" ;;
  esac
  inc export "local:$name" "$dest/instance.tar.gz" --project default
  sudo test -s "$dest/instance.tar.gz"
  sudo chmod 0600 "$dest/instance.tar.gz"
  jq -n --arg name "$name" --arg uuid "$uuid" --arg workload "$workload" \
    '{name:$name,uuid:$uuid,workload:$workload,project:"default"}' | sudo tee "$dest/identity.json" >/dev/null
  sudo chmod 0600 "$dest/identity.json"
  sudo sh -ec 'cd "$1"; umask 077; sha256sum instance.tar.gz identity.json > SHA256SUMS.partial; sha256sum -c SHA256SUMS.partial; mv -T SHA256SUMS.partial SHA256SUMS' sh "$dest"
  echo "Export complete (restore not yet verified): $dest"
}

create_artifact() {
  local workload=$1 name=$2 disk=$3 cpu=$4 memory=$5 out=$6 base alias
  valid_workload "$workload" &&
    [[ $disk =~ ^[1-9][0-9]*GiB$ && $cpu =~ ^[1-9][0-9]*$ && $memory =~ ^[1-9][0-9]*GiB$ && $out == /nix/store/* ]] ||
    die "Invalid workload image or resource request" 2
  test -s "$out/metadata.tar.xz" && test -s "$out/nixos.qcow2" || die "Incomplete image: $out"
  base=${out##*/}
  alias="nix-${base%%-*}"
  if ! inc image info "local:$alias" --project default >/dev/null 2>&1; then
    inc image import "$out/metadata.tar.xz" "$out/nixos.qcow2" local: --alias "$alias" --project default
  fi
  inc launch "local:$alias" "local:$name" --project default --vm \
    -c security.secureboot=false -c boot.autostart=true -c security.protection.delete=true \
    -c "limits.cpu=$cpu" -c "limits.memory=$memory" -c "user.nixfiles.workload=$workload" -d "root,size=$disk"
  ready "$name"
}

backup_artifact() {
  local name=$1 dest=$2 identity
  identity=$(managed_identity "$name")
  bundle "$name" "$dest" "${identity%%$'\n'*}" "${identity#*$'\n'}"
}

update_artifact() {
  local name=$1 dest=$2 expected_workload=$3 expected_uuid=$4 candidate=$5
  local identity workload uuid old active profile requisites
  identity=$(managed_identity "$name")
  workload=${identity%%$'\n'*}
  uuid=${identity#*$'\n'}
  [[ $workload == "$expected_workload" && $uuid == "$expected_uuid" && $candidate == /nix/store/* ]] ||
    die "Instance identity or candidate changed" 2
  test -x "$candidate/bin/switch-to-configuration"
  echo "Phase: verify incumbent readiness" >&2
  ready "$name"
  old=$(guest "$name" readlink -e /run/current-system)
  printf 'Old generation: %s\nCandidate: %s\nBackup: %s\n' "$old" "$candidate" "$dest"
  echo "Phase: export stopped incumbent" >&2
  bundle "$name" "$dest" "$workload" "$uuid"
  echo "Phase: restart incumbent and verify readiness" >&2
  inc start "local:$name" --project default
  ready "$name"
  echo "Phase: import candidate closure" >&2
  # Check query success independently, and preserve each store path as one arg.
  requisites=$(nix-store -qR "$candidate")
  local -a paths
  mapfile -t paths <<< "$requisites"
  nix-store --export "${paths[@]}" | guest_stream "$name" nix-store --import
  echo "Phase: set release profile" >&2
  guest "$name" nix-env -p /nix/var/nix/profiles/system --set "$candidate"
  echo "Phase: activate candidate" >&2
  guest "$name" "$candidate/bin/switch-to-configuration" switch
  active=$(guest "$name" readlink -e /run/current-system)
  profile=$(guest "$name" readlink -e /nix/var/nix/profiles/system)
  [[ $active == "$candidate" && $profile == "$candidate" ]] ||
    die "Active and boot profile closures do not match candidate"
  ready "$name"
  echo "Release active and ready; backup: $dest"
}

# A single native build port holds its GC root through the compound operation.
with_release() (
  local output=$1 callback=$2; shift 2
  local build_root release
  build_root=$(mktemp -d)
  trap 'rm -rf -- "$build_root"' EXIT
  nix build --out-link "$build_root/result" ".#$output"
  release=$(readlink -e "$build_root/result")
  "$callback" "$@" "$release"
)

create_release() {
  local workload=$1 name=$2
  valid_workload "$workload" && valid_name "$name" || die "Invalid workload or name" 2
  with_release "neko7-$workload-image" locked_create "$@"
}
locked_create() { with_lock "$2" create_artifact "$@"; }

update_release() {
  local name=$1 dest=$2 identity workload uuid
  valid_name "$name" && [[ $dest == /* ]] || die "Invalid name or backup path" 2
  identity=$(managed_identity "$name")
  workload=${identity%%$'\n'*}
  uuid=${identity#*$'\n'}
  with_release "neko7-$workload-system" confirm_update "$name" "$dest" "$workload" "$uuid"
}
confirm_update() {
  local confirm
  printf 'Offline backup and update %s. Type instance name: ' "$1"
  read -r confirm
  [[ $confirm == "$1" ]] || die "Cancelled"
  with_lock "$1" update_artifact "$@"
}

[[ $(hostname -s) == neko7 ]] || die "Run on neko7" 2
action=${1:?}; shift
case "$action" in
  create-release) [[ $# == 5 ]] || exit 2; create_release "$@" ;;
  update-release) [[ $# == 2 ]] || exit 2; update_release "$@" ;;
  new) [[ $# == 6 ]] || exit 2; locked_create "$@" ;;
  backup) [[ $# == 2 ]] || exit 2; with_lock "$1" backup_artifact "$@" ;;
  update) [[ $# == 5 ]] || exit 2; with_lock "$1" update_artifact "$@" ;;
  *) die "Unknown instance operation: $action" 2 ;;
esac
