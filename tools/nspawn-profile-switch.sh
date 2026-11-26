#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'Profile switch refused: %s\n' "$*" >&2; exit 1; }
(( EUID == 0 )) || fail 'root operator required'
[[ $# -ge 3 ]] || fail 'usage: NAME EXPECTED_CURRENT --set RELEASE | --rollback'
name=$1 expected=$2 action=$3
shift 3
[[ $name =~ ^[a-z][a-z0-9-]{0,62}$ ]] || fail 'invalid container name'
unit="container@$name.service"
profile="/nix/var/nix/profiles/per-container/$name/system"
valid_release() { [[ $1 == /nix/store/* && $(readlink -e -- "$1") == "$1" && -x $1/init ]]; }
valid_release "$expected" || fail 'invalid expected release'
case "$action" in
  --set) [[ $# == 1 ]] && valid_release "$1" || fail 'invalid candidate release' ;;
  --rollback) [[ $# == 0 ]] || fail 'unexpected rollback argument' ;;
  *) fail 'unknown profile operation' ;;
esac
[[ -L $profile && $(readlink -e -- "$profile") == "$expected" ]] || fail 'current release changed; reconcile before retry'

declare -A state
observe() {
  local output key value
  state=()
  output=$(systemctl show --all --no-pager --property=LoadState,ActiveState,SubState,Result,Job,MainPID,ControlPID,ControlGroup,TasksCurrent,ExecMainCode,ExecMainStatus "$unit") || fail "cannot inspect $unit"
  while IFS='=' read -r key value; do
    case "$key" in
      LoadState|ActiveState|SubState|Result|Job|MainPID|ControlPID|ControlGroup|TasksCurrent|ExecMainCode|ExecMainStatus) state[$key]=$value ;;
    esac
  done <<< "$output"
  [[ ${state[LoadState]-} == loaded && ${state[Result]-} == success && ${state[Job]-missing} =~ ^(0)?$ ]] || fail "unsafe $unit: $output"
}
clean_inactive() {
  [[ ${state[ActiveState]-} == inactive && ${state[SubState]-} == dead &&
     ${state[MainPID]-} == 0 && ${state[ControlPID]-} == 0 &&
     ( ${state[ControlGroup]-missing} == '' || ${state[TasksCurrent]-} == 0 ) &&
     ${state[ExecMainCode]-} =~ ^[01]$ && ${state[ExecMainStatus]-} == 0 ]]
}
observe
if [[ ${state[ActiveState]-} == active && ${state[SubState]-} == running && ${state[MainPID]-} =~ ^[1-9][0-9]*$ && ${state[ControlPID]-} == 0 ]]; then
  systemctl stop "$unit" || fail "stop command failed for $unit"
  observe
fi
clean_inactive || fail "$unit is not cleanly stopped"
mounts=$(findmnt --kernel --noheadings --raw --output TARGET) || fail 'cannot inspect host mounts'
while IFS= read -r target; do
  case "$target" in
    /run/systemd/nspawn/unix-export/"$name"|/run/systemd/nspawn/unix-export/"$name"/*|/run/systemd/nspawn/propagate/"$name"|/run/systemd/nspawn/propagate/"$name"/*) fail "stale nspawn mount: $target" ;;
  esac
done <<< "$mounts"
machines=$(machinectl list --no-legend --no-pager --full) || fail 'cannot inspect registered machines'
while read -r machine _; do
  [[ $machine != "$name" ]] || fail "machine still registered: $name"
done <<< "$machines"
[[ $(readlink -e -- "$profile") == "$expected" ]] || fail 'current release changed during stop'
nix-env --profile "$profile" "$action" "$@"
systemctl start "$unit"
