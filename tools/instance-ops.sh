#!/usr/bin/env bash
# No persistent controller state. The operator's native Incus and Nix state
# remains authoritative. All compound operations serialize on a host-local lock.
set -euo pipefail
[[ $(hostname -s) == neko7 ]] || { echo "Run on neko7" >&2; exit 2; }
action=${1:?}; shift
case "$action" in
  new) [[ $# == 6 ]] || exit 2; workload=$1 name=$2 ;;
  backup) [[ $# == 2 ]] || exit 2; name=$1 ;;
  update) [[ $# == 5 ]] || exit 2; name=$1 ;;
  *) exit 2 ;;
esac
[[ $name =~ ^[a-z][a-z0-9-]{0,62}$ ]] || exit 2
umask 007
exec 9>"/run/lock/neko7-instances/$name.lock"
flock -n 9 || { echo "Instance operation already running: $name" >&2; exit 1; }
umask 077
target="local:$name"
inc() { sudo incus "$@"; }
get() { inc config get "$target" "$1" --project default; }
# Incus agent supplies a generic Linux PATH, not a NixOS login environment.
# Explicitly resolve the guest's active system and wrappers, never host paths.
guest_path=/run/wrappers/bin:/run/current-system/sw/bin
guest() { inc exec "$target" --project default --env "PATH=$guest_path" -- "$@"; }
managed() {
  workload=$(get user.nixfiles.workload)
  uuid=$(get volatile.uuid)
  [[ $workload =~ ^[a-z][a-z0-9-]*$ && -n $uuid ]] || { echo "Not a managed workload" >&2; exit 1; }
}
ready() {
  # Count elapsed wall time, not attempts: an unresponsive VM agent
  # can otherwise make 120 CLI requests take an hour or more.
  local budget=${NEKO7_READINESS_TIMEOUT:-300}
  [[ $budget =~ ^[1-9][0-9]{0,3}$ ]] && (( budget <= 900 )) || { echo "Invalid readiness budget (1..900 seconds)" >&2; return 2; }
  local deadline=$((SECONDS + budget)) remaining probe
  while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    probe=$((remaining < 30 ? remaining : 30))
    if timeout -k 5s "${probe}s" sudo incus exec "$target" --project default --env "PATH=$guest_path" -- /etc/neko7/readiness; then
      return 0
    fi
    if (( SECONDS + 2 < deadline )); then sleep 2; else break; fi
  done
  echo "Readiness failed after bounded wait; inspect $target, do not automatically roll back data" >&2
  return 1
}
bundle() {
  local dest=$1 status
  [[ $dest == /* ]] || exit 2
  # mkdir is the atomic no-overwrite admission. Failed exports leave a
  # partial bundle without SHA256SUMS; never treat it as a valid backup.
  parent=$(dirname "$dest")
  sudo test -d "$parent"
  mode=$(sudo stat -Lc %a "$parent")
  (( (8#$mode & 077) == 0 )) || { echo "Backup parent must be private (0700)" >&2; exit 1; }
  sudo mkdir -m 0700 -- "$dest"
  status=$(inc list local: --project default --format json | jq -er --arg name "$name" '.[] | select(.name == $name) | .status')
  case "$status" in
    Running) inc stop "$target" --project default ;;
    Stopped) ;;
    *) echo "Unexpected status: $status" >&2; exit 1 ;;
  esac
  inc export "$target" "$dest/instance.tar.gz" --project default
  sudo test -s "$dest/instance.tar.gz"
  sudo chmod 0600 "$dest/instance.tar.gz"
  jq -n --arg name "$name" --arg uuid "$uuid" --arg workload "$workload" \
    '{name:$name,uuid:$uuid,workload:$workload,project:"default"}' | sudo tee "$dest/identity.json" >/dev/null
  sudo chmod 0600 "$dest/identity.json"
  sudo sh -ec 'cd "$1"; umask 077; sha256sum instance.tar.gz identity.json > SHA256SUMS.partial; sha256sum -c SHA256SUMS.partial; mv -T SHA256SUMS.partial SHA256SUMS' sh "$dest"
  echo "Export complete (restore not yet verified): $dest"
}
case "$action" in
  new)
    disk=$3 cpu=$4 memory=$5 out=$6
    [[ $workload =~ ^[a-z][a-z0-9-]*$ && $disk =~ ^[1-9][0-9]*GiB$ && $cpu =~ ^[1-9][0-9]*$ && $memory =~ ^[1-9][0-9]*GiB$ && $out == /nix/store/* ]] || exit 2
    test -s "$out/metadata.tar.xz" && test -s "$out/nixos.qcow2" || exit 1
    base=${out##*/}
    alias="nix-${base%%-*}"
    if ! inc image info "local:$alias" --project default >/dev/null 2>&1; then
      inc image import "$out/metadata.tar.xz" "$out/nixos.qcow2" local: --alias "$alias" --project default
    fi
    inc launch "local:$alias" "$target" --project default --vm \
      -c security.secureboot=false -c boot.autostart=true -c security.protection.delete=true \
      -c "limits.cpu=$cpu" -c "limits.memory=$memory" -c "user.nixfiles.workload=$workload" -d "root,size=$disk"
    ready
    ;;
  backup)
    managed
    bundle "$2"
    ;;
  update)
    dest=$2 expected_workload=$3 expected_uuid=$4 candidate=$5
    managed
    [[ $workload == "$expected_workload" && $uuid == "$expected_uuid" && $candidate == /nix/store/* ]] || exit 2
    test -x "$candidate/bin/switch-to-configuration"
    # Refuse concurrent identity changes and verify the current release is usable.
    ready
    old=$(guest readlink -e /run/current-system)
    printf 'Old generation: %s\nCandidate: %s\nBackup: %s\n' "$old" "$candidate" "$dest"
    bundle "$dest"
    inc start "$target" --project default
    ready
    nix-store --export $(nix-store -qR "$candidate") | guest nix-store --import
    guest nix-env -p /nix/var/nix/profiles/system --set "$candidate"
    guest "$candidate/bin/switch-to-configuration" switch
    active=$(guest readlink -e /run/current-system)
    profile=$(guest readlink -e /nix/var/nix/profiles/system)
    [[ $active == "$candidate" && $profile == "$candidate" ]] || exit 1
    ready
    echo "Release active and ready; backup: $dest"
    ;;
esac
