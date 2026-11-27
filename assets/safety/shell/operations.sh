# shellcheck shell=bash
# Private sourced API. Use one operation per Bash subshell. See README.md.

_safety_report() {
  printf 'safety-shell: %s\n' "$1" >&2
}

_safety_canonical_dir() {
  local resolved
  # Wait for realpath to exit before returning; an asynchronous child can
  # retain the inherited flock descriptor. The sentinel preserves newlines.
  [[ $1 == /* && $1 != / && -d $1 ]] &&
    resolved=$(@coreutils@/bin/realpath -e -- "$1" && printf '.') &&
    [[ $resolved == "$1"
}

_safety_root_current() {
  _safety_canonical_dir "$_safety_root" &&
    [[ $_safety_root -ef /proc/self/fd/$_safety_root_fd ]]
}

_safety_owned_stage() {
  [[ -n ${safety_stage_fd-} && -f $safety_stage_path && ! -L $safety_stage_path &&
    -O $safety_stage_path && $safety_stage_path -ef /proc/self/fd/$safety_stage_fd ]]
}

_safety_native() {
  @python3@/bin/python3 -I @native@ "$@"
}

_safety_confirm_final() {
  local final=/proc/self/fd/$_safety_root_fd/$_safety_final_leaf
  if _safety_root_current && [[ ! -L $final && $final -ef /proc/self/fd/$safety_stage_fd ]]; then
    return 0
  fi
  _safety_phase=unknown
  _safety_report 'OutcomeUnknown: final could not be confirmed after link'
  return 75
}

safety_lock() {
  local mode lock status
  if [[ $# != 1 || -v _safety_root_fd ]]; then
    _safety_report 'Denied: expected one root and one operation per subshell'
    return 64
  fi
  if ! _safety_canonical_dir "$1"; then
    _safety_report 'Unsupported: root must be an existing canonical absolute directory'
    return 69
  fi
  readonly _safety_root=$1
  exec {_safety_root_fd}< "$_safety_root" || return "$?"
  readonly _safety_root_fd
  mode=$(@coreutils@/bin/stat -Lc '%a' -- "/proc/self/fd/$_safety_root_fd") || return "$?"
  if ! _safety_root_current || [[ ! -O $_safety_root ]] || (( 8#$mode & 022 )); then
    _safety_report 'Unsupported: root must be stable, owned by the caller and protected from group and other writes'
    return 69
  fi

  lock=/proc/self/fd/$_safety_root_fd/.safety.lock
  if [[ ! -f $lock || -L $lock || ! -O $lock ]]; then
    _safety_report 'Denied: provision an owned regular .safety.lock first'
    return 64
  fi
  exec {_safety_lock_fd}< "$lock" || return "$?"
  readonly _safety_lock_fd
  if [[ ! -f $lock || -L $lock || ! $lock -ef /proc/self/fd/$_safety_lock_fd ]]; then
    _safety_report 'Unsupported: lock entry changed during open'
    return 69
  fi
  @util-linux@/bin/flock --exclusive --nonblock --conflict-exit-code 73 -- "$_safety_lock_fd" || {
    status=$?
    if (( status == 73 )); then
      _safety_report 'Conflict: operation lock is held'
    fi
    return "$status"
  }
  readonly _safety_locked=1
}

safety_stage() {
  if [[ $# != 1 || ! -v _safety_locked || -v _safety_final_leaf ]]; then
    _safety_report 'Denied: expected a held lock and one new stage'
    return 64
  fi
  case $1 in
    ''|.|..|*/*|.safety.lock|.safety-stage.*)
      _safety_report 'Denied: final must be a single, non-reserved leaf'
      return 64
      ;;
  esac
  if ! _safety_root_current; then
    _safety_report 'Unsupported: root moved before staging'
    return 69
  fi
  readonly _safety_final_leaf=$1
  safety_stage_path=$(
    umask 077
    @coreutils@/bin/mktemp -- "/proc/self/fd/$_safety_root_fd/.safety-stage.XXXXXXXXXX"
  ) || return "$?"
  readonly safety_stage_path
  exec {safety_stage_fd}<> "$safety_stage_path" || return "$?"
  readonly safety_stage_fd
  if ! _safety_owned_stage; then
    _safety_report 'Unsupported: stage entry changed during open'
    return 69
  fi
  _safety_phase=staged
}

safety_publish_new() {
  local metadata status
  if [[ ${_safety_phase-} != staged ]]; then
    _safety_report 'Denied: expected a staged file before publication'
    return 64
  fi
  if ! _safety_root_current || ! _safety_owned_stage; then
    _safety_report 'Unsupported: root or stage changed before publication'
    return 69
  fi
  metadata=$(@coreutils@/bin/stat -Lc '%a:%h' -- "/proc/self/fd/$safety_stage_fd") || return "$?"
  if [[ $metadata != 600:1 ]]; then
    _safety_report 'Denied: stage must be private (0600) and have one link'
    return 64
  fi
  _safety_native fsync "$safety_stage_fd" || return "$?"
  if ! _safety_root_current || ! _safety_owned_stage; then
    _safety_report 'Unsupported: root or stage changed before link'
    return 69
  fi

  # From the moment link starts, an interruption may leave a visible final.
  _safety_phase=publishing
  if _safety_native link "$_safety_root_fd" "${safety_stage_path##*/}" "$_safety_final_leaf"; then
    _safety_confirm_final || return "$?"
    _safety_native fsync "$_safety_root_fd" || {
      status=$?
      _safety_phase=unknown
      _safety_report "OutcomeUnknown: final may be visible; parent fsync status $status"
      return "$status"
    }
    _safety_confirm_final || return "$?"
    _safety_phase=durable
  else
    status=$?
    case $status in
      69|73|74) _safety_phase=failed ;;
      *)
        _safety_phase=unknown
        _safety_report "OutcomeUnknown: link did not confirm publication (status $status)"
        ;;
    esac
    return "$status"
  fi
}

# EXIT handler. Keep the original status if cleanup also fails.
safety_finish() {
  local status=$1 cleanup_status=0
  case ${_safety_phase-} in
    publishing)
      _safety_report 'OutcomeUnknown: interrupted during publication; inspect final and stage'
      if (( status == 0 )); then
        status=75
      fi
      exit "$status"
      ;;
    unknown) exit "$((status != 0 ? status : 75))" ;;
  esac
  if [[ -v _safety_final_leaf && -v safety_stage_path ]]; then
    if _safety_root_current && _safety_owned_stage; then
      @coreutils@/bin/rm -- "$safety_stage_path" || cleanup_status=$?
    else
      cleanup_status=69
    fi
    if (( cleanup_status != 0 )); then
      if [[ ${_safety_phase-} == durable ]]; then
        _safety_report "CleanupFailed: final published and flushed; stage cleanup status $cleanup_status"
      else
        _safety_report "CleanupFailed: stage cleanup status $cleanup_status"
      fi
    fi
  fi
  exit "$((status != 0 ? status : cleanup_status))"
}
\n.' ]]
}

_safety_root_current() {
  _safety_canonical_dir "$_safety_root" &&
    [[ $_safety_root -ef /proc/self/fd/$_safety_root_fd ]]
}

_safety_owned_stage() {
  [[ -n ${safety_stage_fd-} && -f $safety_stage_path && ! -L $safety_stage_path &&
    -O $safety_stage_path && $safety_stage_path -ef /proc/self/fd/$safety_stage_fd ]]
}

_safety_native() {
  @python3@/bin/python3 -I @native@ "$@"
}

_safety_confirm_final() {
  local final=/proc/self/fd/$_safety_root_fd/$_safety_final_leaf
  if _safety_root_current && [[ ! -L $final && $final -ef /proc/self/fd/$safety_stage_fd ]]; then
    return 0
  fi
  _safety_phase=unknown
  _safety_report 'OutcomeUnknown: final could not be confirmed after link'
  return 75
}

safety_lock() {
  local mode lock status
  if [[ $# != 1 || -v _safety_root_fd ]]; then
    _safety_report 'Denied: expected one root and one operation per subshell'
    return 64
  fi
  if ! _safety_canonical_dir "$1"; then
    _safety_report 'Unsupported: root must be an existing canonical absolute directory'
    return 69
  fi
  readonly _safety_root=$1
  exec {_safety_root_fd}< "$_safety_root" || return "$?"
  readonly _safety_root_fd
  mode=$(@coreutils@/bin/stat -Lc '%a' -- "/proc/self/fd/$_safety_root_fd") || return "$?"
  if ! _safety_root_current || [[ ! -O $_safety_root ]] || (( 8#$mode & 022 )); then
    _safety_report 'Unsupported: root must be stable, owned by the caller and protected from group and other writes'
    return 69
  fi

  lock=/proc/self/fd/$_safety_root_fd/.safety.lock
  if [[ ! -f $lock || -L $lock || ! -O $lock ]]; then
    _safety_report 'Denied: provision an owned regular .safety.lock first'
    return 64
  fi
  exec {_safety_lock_fd}< "$lock" || return "$?"
  readonly _safety_lock_fd
  if [[ ! -f $lock || -L $lock || ! $lock -ef /proc/self/fd/$_safety_lock_fd ]]; then
    _safety_report 'Unsupported: lock entry changed during open'
    return 69
  fi
  @util-linux@/bin/flock --exclusive --nonblock --conflict-exit-code 73 -- "$_safety_lock_fd" || {
    status=$?
    if (( status == 73 )); then
      _safety_report 'Conflict: operation lock is held'
    fi
    return "$status"
  }
  readonly _safety_locked=1
}

safety_stage() {
  if [[ $# != 1 || ! -v _safety_locked || -v _safety_final_leaf ]]; then
    _safety_report 'Denied: expected a held lock and one new stage'
    return 64
  fi
  case $1 in
    ''|.|..|*/*|.safety.lock|.safety-stage.*)
      _safety_report 'Denied: final must be a single, non-reserved leaf'
      return 64
      ;;
  esac
  if ! _safety_root_current; then
    _safety_report 'Unsupported: root moved before staging'
    return 69
  fi
  readonly _safety_final_leaf=$1
  safety_stage_path=$(
    umask 077
    @coreutils@/bin/mktemp -- "/proc/self/fd/$_safety_root_fd/.safety-stage.XXXXXXXXXX"
  ) || return "$?"
  readonly safety_stage_path
  exec {safety_stage_fd}<> "$safety_stage_path" || return "$?"
  readonly safety_stage_fd
  if ! _safety_owned_stage; then
    _safety_report 'Unsupported: stage entry changed during open'
    return 69
  fi
  _safety_phase=staged
}

safety_publish_new() {
  local metadata status
  if [[ ${_safety_phase-} != staged ]]; then
    _safety_report 'Denied: expected a staged file before publication'
    return 64
  fi
  if ! _safety_root_current || ! _safety_owned_stage; then
    _safety_report 'Unsupported: root or stage changed before publication'
    return 69
  fi
  metadata=$(@coreutils@/bin/stat -Lc '%a:%h' -- "/proc/self/fd/$safety_stage_fd") || return "$?"
  if [[ $metadata != 600:1 ]]; then
    _safety_report 'Denied: stage must be private (0600) and have one link'
    return 64
  fi
  _safety_native fsync "$safety_stage_fd" || return "$?"
  if ! _safety_root_current || ! _safety_owned_stage; then
    _safety_report 'Unsupported: root or stage changed before link'
    return 69
  fi

  # From the moment link starts, an interruption may leave a visible final.
  _safety_phase=publishing
  if _safety_native link "$_safety_root_fd" "${safety_stage_path##*/}" "$_safety_final_leaf"; then
    _safety_confirm_final || return "$?"
    _safety_native fsync "$_safety_root_fd" || {
      status=$?
      _safety_phase=unknown
      _safety_report "OutcomeUnknown: final may be visible; parent fsync status $status"
      return "$status"
    }
    _safety_confirm_final || return "$?"
    _safety_phase=durable
  else
    status=$?
    case $status in
      69|73|74) _safety_phase=failed ;;
      *)
        _safety_phase=unknown
        _safety_report "OutcomeUnknown: link did not confirm publication (status $status)"
        ;;
    esac
    return "$status"
  fi
}

# EXIT handler. Keep the original status if cleanup also fails.
safety_finish() {
  local status=$1 cleanup_status=0
  case ${_safety_phase-} in
    publishing)
      _safety_report 'OutcomeUnknown: interrupted during publication; inspect final and stage'
      if (( status == 0 )); then
        status=75
      fi
      exit "$status"
      ;;
    unknown) exit "$((status != 0 ? status : 75))" ;;
  esac
  if [[ -v _safety_final_leaf && -v safety_stage_path ]]; then
    if _safety_root_current && _safety_owned_stage; then
      @coreutils@/bin/rm -- "$safety_stage_path" || cleanup_status=$?
    else
      cleanup_status=69
    fi
    if (( cleanup_status != 0 )); then
      if [[ ${_safety_phase-} == durable ]]; then
        _safety_report "CleanupFailed: final published and flushed; stage cleanup status $cleanup_status"
      else
        _safety_report "CleanupFailed: stage cleanup status $cleanup_status"
      fi
    fi
  fi
  exit "$((status != 0 ? status : cleanup_status))"
}
