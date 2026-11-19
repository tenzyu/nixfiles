# shellcheck shell=bash

export LC_ALL=C
unset CDPATH ENV BASH_ENV
cd /

fail() {
  local status=$1
  shift
  printf 'minecraft: %s\n' "$*" >&2
  exit "$status"
}

if (( EUID != host_uid )); then
  fail 64 'Denied: authorize the fixed Minecraft operator before taking its lock'
fi

inside() {
  # Resolve arbitrary admin commands in the guest system profile as before.
  env -i PATH="$PATH:/run/current-system/sw/bin" TERM="${TERM:-dumb}" \
    "$container" run "$containerName" -- "$@"
}

guest_ctl() { inside "$guest_systemctl" --no-ask-password "$@"; }
host_ctl() { env -i PATH="$PATH" "$host_systemctl" --no-ask-password "$@"; }

readonly job_guard="${lockPath}.job"
guard_present() { [[ -e $job_guard || -L $job_guard ]]; }

lock_lifecycle() {
  local directory=${lockPath%/*} entry metadata status
  # /run (or the fixture directory) and the policy directory must be
  # canonical and root-owned before we open a pathname as the operator.
  [[ $lock_gid =~ ^[0-9]+$ ]] || fail 69 'Unsupported: native operator group unavailable'
  [[ $(realpath -e -- "$directory") == "$directory" &&
    $(stat -fLc '%T' -- "$directory") == "$lock_fs" ]] ||
    fail 69 'Unsupported: expected the native lock directory on trusted local /run'
  entry=$directory
  while :; do
    metadata=$(stat -Lc '%u:%a' -- "$entry") || fail 69 'Unsupported: cannot inspect lock ancestry'
    if [[ ${metadata%:*} != "$host_uid" ]] || (( 8#${metadata#*:} & 022 )); then
      fail 69 'Unsupported: unsafe lifecycle lock ancestry'
    fi
    [[ $entry != "$lock_boundary" && $entry != / ]] || break
    entry=${entry%/*}
    entry=${entry:-/}
  done
  [[ $(stat -Lc '%u:%g:%a' -- "$directory") == "$host_uid:$lock_gid:750" &&
    -f $lockPath && ! -L $lockPath &&
    $(stat -Lc '%u:%g:%a:%h' -- "$lockPath") == "$host_uid:$lock_gid:440:1" ]] ||
    fail 69 'Unsupported: expected the native root:wheel 0440 regular lifecycle inode'
  exec {host_lock_fd}< "$lockPath" || fail 69 'Unsupported: cannot open native lifecycle lock'
  [[ $lockPath -ef /proc/self/fd/$host_lock_fd ]] ||
    fail 69 'Unsupported: lifecycle lock changed while opening'
  flock --exclusive --nonblock --conflict-exit-code 73 -- "$host_lock_fd" || {
    status=$?
    if ((status == 73)); then
      fail 73 "Conflict: another managed Minecraft operation holds the lifecycle lock; inspect with 'game diagnose minecraft'"
    fi
    fail "$status" 'Unsupported: could not take the lifecycle flock'
  }
  host_inode=$(stat -Lc '%d:%i' -- "/proc/self/fd/$host_lock_fd")
  readonly host_lock_fd host_inode
  if guard_present; then
    fail 69 "OutcomeUnknown: previous native job unconfirmed ($job_guard); run 'game diagnose minecraft' and follow the recovery runbook"
  fi
}

# Keep a trusted waiter and its descriptor alive through terminal interruption.
# systemctl waits for the manager job by default, so do not cancel the client
# while a queued service mutation can still run.
protected_call() (
  trap '' HUP INT TERM PIPE
  local status=0
  "$@" || status=$?
  exit "$status"
)

native_job() (
  trap '' HUP INT TERM PIPE
  local manager=$1 verb=$2 unit=$3 status=0
  # A manager job can outlive every client on a hard kill or bus failure.
  # Keep an admission guard in the protected host directory until the client
  # confirms successful completion. A nonzero exit does not establish whether
  # the manager accepted the job or finished it.
  mkdir -m 0700 -- "$job_guard" || exit "$?"
  "${manager}_ctl" "$verb" "$unit" || status=$?
  if ((status != 0)); then
    fail "$status" "OutcomeUnknown: $manager $verb $unit returned $status; guard retained at $job_guard; run 'game diagnose minecraft'"
  fi
  rmdir -- "$job_guard" || fail "$?" "Admission: $manager $verb $unit completed; could not remove $job_guard"
)

# Arbitrary admin commands must never receive the lifecycle descriptor.
# A trusted waiter owns it for the foreground invocation.
admin_command() (
  trap ':' HUP INT TERM
  local status=0
  (
    exec {host_lock_fd}<&-
    inside "$@"
  ) || status=$?
  exit "$status"
)

unit_properties() {
  "$1" show --all --no-pager \
    --property=LoadState,ActiveState,SubState,Result,Job,MainPID,ControlPID,ControlGroup,TasksCurrent,ExecMainPID,ExecMainCode,ExecMainStatus \
    "$2"
}

declare -A unit_state
observe() {
  local output key value
  unit_state=()
  output=$(unit_properties "$@") || return "$?"
  while IFS='=' read -r key value; do
    case "$key" in
      LoadState|ActiveState|SubState|Result|Job|MainPID|ControlPID|ControlGroup|TasksCurrent|ExecMainPID|ExecMainCode|ExecMainStatus)
        unit_state[$key]=$value ;;
    esac
  done <<< "$output"
  [[ ${unit_state[LoadState]-} == loaded && ${unit_state[Job]-missing} =~ ^(0)?$ &&
    ${unit_state[Result]-} == success ]]
}

clean_inactive() {
  [[ ${unit_state[ActiveState]-} == inactive && ${unit_state[SubState]-} == dead &&
    ${unit_state[MainPID]-} == 0 && ${unit_state[ControlPID]-} == 0 &&
    ( ${unit_state[ControlGroup]-missing} == "" || ${unit_state[TasksCurrent]-} == 0 ) &&
    ${unit_state[ExecMainCode]-} =~ ^[01]$ && ${unit_state[ExecMainStatus]-} == 0 ]]
}

active() {
  [[ ${unit_state[ActiveState]-} == active && ${unit_state[SubState]-} == running &&
    ${unit_state[MainPID]-} =~ ^[1-9][0-9]*$ && ${unit_state[ControlPID]-} == 0 ]]
}

state_description() {
  printf 'ActiveState=%s SubState=%s Result=%s Job=%s' \
    "${unit_state[ActiveState]-unknown}" "${unit_state[SubState]-unknown}" \
    "${unit_state[Result]-unknown}" "${unit_state[Job]-unknown}"
}

host_state() { observe host_ctl "$containerUnit"; }
guest_state() { observe guest_ctl "$guestUnit"; }
running() { host_state && active && guest_state && active; }

status_report() {
  if ! host_state; then
    fail 69 "container state unavailable or unsafe ($(state_description))"
  elif clean_inactive; then
    echo 'minecraft    container inactive / guest state unavailable'
  elif ! active; then
    fail 69 "container state unsupported ($(state_description))"
  elif ! guest_state; then
    fail 69 "guest unit state unavailable or unsafe ($(state_description))"
  elif active; then
    echo 'minecraft    running'
  elif clean_inactive; then
    echo 'minecraft    container up / server inactive'
  else
    fail 69 "guest state unsupported ($(state_description))"
  fi
}

manager_report() {
  local manager=$1 unit=$2 ctl=${1}_ctl status=0
  printf '\n%s unit %s\n' "$manager" "$unit"
  if ! unit_properties "$ctl" "$unit"; then
    printf '%s unit properties unavailable\n' "$manager" >&2
    status=69
  fi
  printf '\n%s manager jobs\n' "$manager"
  if ! "$ctl" list-jobs --no-pager --full; then
    printf '%s job queue unavailable\n' "$manager" >&2
    status=69
  fi
  return "$status"
}

diagnose() {
  local status=0
  if guard_present; then
    printf 'Admission: guard present at %s\n' "$job_guard"
    stat -c 'type=%F owner=%u:%g mode=%a last-change=%z' -- "$job_guard" || status=69
  else
    printf 'Admission: no guard observed at %s\n' "$job_guard"
  fi
  printf 'Unit and job listings are snapshots. Reconcile the previous request under the lifecycle lock before clearing a guard.\n'
  manager_report host "$containerUnit" || status=$?
  manager_report guest "$guestUnit" || status=$?
  return "$status"
}

as_archive_user() {
  env -i PATH="$PATH" "$drop_privileges" --reuid "$archiveUid" --regid "$archiveGid" \
    --clear-groups --no-new-privs -- "$writer" "$1" "$2" "$host_lock_fd" "$host_inode"
}

backup() {
  local previous_pid='' timestamp leaf publication status=0
  host_state || fail 69 "backup refused before stop: container observation failed ($(state_description))"
  active || fail 69 "backup refused before stop: container must already be running to observe the guest ($(state_description))"
  guest_state || fail 69 "backup refused before stop: guest observation failed ($(state_description))"
  if active; then
    previous_pid=${unit_state[MainPID]}
  elif ! clean_inactive; then
    fail 69 "backup refused before stop: guest is not cleanly inactive or running ($(state_description))"
  fi

  timestamp=$("$clock" +%Y%m%d-%H%M%S) || fail "$?" 'backup refused before stop: date failed'
  leaf=minecraft-$timestamp.tar.gz
  [[ $leaf =~ ^minecraft-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] || fail 69 'Unsupported: invalid archive timestamp'
  as_archive_user preflight "$leaf" || fail "$?" 'backup refused before stop: archive preflight failed'

  if ! { host_state && active && guest_state; }; then
    fail 69 "backup refused before stop: state changed during preflight ($(state_description))"
  fi
  if [[ -n $previous_pid ]]; then
    active && [[ ${unit_state[MainPID]} == "$previous_pid" ]] ||
      fail 69 "backup refused before stop: guest changed during preflight ($(state_description))"
    native_job guest stop "$guestUnit" ||
      fail "$?" 'Archive: not attempted; stop command failed, inspect guest unit before retrying'
    guest_state && clean_inactive && [[ ${unit_state[ExecMainCode]} == 1 &&
      ${unit_state[ExecMainPID]-} == "$previous_pid" ]] ||
      fail 69 "Archive: not attempted; clean guest stop unconfirmed ($(state_description))"
  elif ! clean_inactive; then
    fail 69 "backup refused: inactive guest changed during preflight ($(state_description))"
  fi

  publication=$(as_archive_user archive "$leaf") || status=$?
  if [[ $publication != published ]]; then
    if [[ $publication == not-published ]]; then
      printf 'Archive: no new publication (%s/%s; writer status %d)\n' "$backupsDir" "$leaf" "$status" >&2
    else
      printf 'Archive: unconfirmed (OutcomeUnknown, %s/%s; writer status %d)\n' "$backupsDir" "$leaf" "$status" >&2
    fi
    printf 'Resume: skipped; guest was observed inactive before archiving\n' >&2
    return "$((status != 0 ? status : 75))"
  fi
  printf 'Archive: published %s/%s\n' "$backupsDir" "$leaf"
  if ((status != 0)); then
    fail "$status" 'Resume: skipped; published archive needs stage cleanup inspection'
  elif [[ -z $previous_pid ]]; then
    echo 'Resume: unnecessary; guest was already inactive'
  else
    if ! { host_state && active && guest_state && clean_inactive; }; then
      fail 69 "Resume: failed to confirm a stable inactive guest ($(state_description)); archive remains published"
    fi
    native_job guest start "$guestUnit" ||
      fail "$?" 'Resume: failed to confirm guest start; archive remains published'
    if ! { guest_state && active; }; then
      fail 69 "Resume: failed to confirm guest running ($(state_description)); archive remains published"
    fi
    echo 'Resume: guest running'
  fi
}

readonly action=${1:-}
if (($# == 0)); then fail 64 'Denied: expected a Minecraft operation'; fi
shift
case "$action" in
  status|diagnose|start|stop|restart|console|backup|update)
    (($# == 0)) || fail 64 "Denied: $action takes no extra arguments" ;;
  send) (($# == 1)) || fail 64 'Usage: game send minecraft COMMAND' ;;
  exec) (($# > 0)) || fail 64 'Usage: game exec minecraft COMMAND [ARGS...]' ;;
  *) fail 64 'Denied: unknown Minecraft operation' ;;
esac
case "$action" in
  status) status_report; exit ;;
  diagnose) diagnose; exit ;;
esac
lock_lifecycle
trap 'fail 129 "Interrupted: lifecycle operation (HUP); inspect guest and archives"' HUP
trap 'fail 130 "Interrupted: lifecycle operation (INT); inspect guest and archives"' INT
trap 'fail 143 "Interrupted: lifecycle operation (TERM); inspect guest and archives"' TERM

case "$action" in
  start|restart)
    native_job host start "$containerUnit"
    native_job guest "$action" "$guestUnit"
    ;;
  stop)
    host_state || fail 69 "stop refused: container observation failed ($(state_description))"
    if active; then
      native_job guest stop "$guestUnit"
    elif ! clean_inactive; then
      fail 69 "stop refused: unsupported container state ($(state_description))"
    fi
    ;;
  send)
    running || fail 69 'send refused: Minecraft running state unconfirmed'
    protected_call inside tmux -S /run/minecraft/survival.sock send-keys -l -- "$1"
    protected_call inside tmux -S /run/minecraft/survival.sock send-keys Enter
    ;;
  console)
    running || fail 69 'console refused: Minecraft running state unconfirmed'
    admin_command tmux -S /run/minecraft/survival.sock attach
    ;;
  exec)
    native_job host start "$containerUnit"
    admin_command "$@"
    ;;
  update)
    fail 2 'No update unit for minecraft. Rebuild the NixOS configuration to update Minecraft.'
    ;;
  backup) backup ;;
esac
