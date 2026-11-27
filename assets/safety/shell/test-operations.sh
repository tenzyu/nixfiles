#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

library=$1
native=$2
# shellcheck source=operations.sh
source "$library"

fixture=$(mktemp -d)
trap 'chmod -R u+rwx -- "$fixture"; rm -rf -- "$fixture"' EXIT

fail() {
  printf 'FAIL %s: %s\n' "${case_dir##*/}" "$*" >&2
  exit 1
}

new_case() {
  case_dir=$fixture/$1
  root=$case_dir/root
  mkdir -- "$case_dir"
  mkdir -m 700 -- "$root"
  printf 'lock fixture\n' > "$root/.safety.lock"
  printf 'unrelated\n' > "$root/unrelated"
}

expect_status() {
  local expected=$1 diagnostic=$2 actual=0
  shift 2
  "$@" 2>"$case_dir/stderr" || actual=$?
  if [[ $actual != "$expected" || $(<"$case_dir/stderr") != *"$diagnostic"* ]]; then
    cat "$case_dir/stderr" >&2
    fail "expected status $expected and diagnostic '$diagnostic', got status $actual"
  fi
}

entry() {
  stat -c '%d:%i:%a:%h:%s' -- "$1"
}

expect_stages() {
  local stages=("$root"/.safety-stage.*)
  (( ${#stages[@]} == $1 )) || fail "expected $1 stages, saw ${#stages[@]}"
}

expect_no_final() {
  [[ ! -e $root/archive && ! -L $root/archive ]] || fail 'unexpected final'
}

expect_final() {
  [[ -f $root/archive && ! -L $root/archive && $(<"$root/archive") == 'complete payload' ]] ||
    fail 'final bytes or type changed'
  [[ $(stat -c %a -- "$root/archive") == 600 ]] || fail 'final mode changed'
}

interrupt_traps() {
  trap 'echo "Interrupted: HUP" >&2; exit 129' HUP
  trap 'echo "Interrupted: INT" >&2; exit 130' INT
  trap 'echo "Interrupted: TERM" >&2; exit 143' TERM
}

write_stage() {
  case $1 in
    partial) printf 'partial'; return 42 ;;
    write-full)
      printf 'partial'
      printf 'synthetic writer: ENOSPC\n' >&2
      return 28
      ;;
    cancel) return 125 ;;
    signal) kill -TERM "$BASHPID" ;;
    *) printf 'complete payload\n' ;;
  esac
}

validate_stage() {
  [[ $1 != invalid && $(<"$safety_stage_path") == 'complete payload' ]] || return 43
}

attempt() (
  local scenario=${1:-success}
  trap 'safety_finish "$?"' EXIT
  interrupt_traps
  safety_lock "$root" || exit "$?"
  safety_stage archive || exit "$?"
  [[ $(stat -c '%a:%h' -- "$safety_stage_path") == 600:1 ]] || fail 'stage is not private'
  write_stage "$scenario" >&"$safety_stage_fd" || exit "$?"
  validate_stage "$scenario" || exit "$?"
  case $scenario in
    stage-replaced)
      mv -- "$safety_stage_path" "$root/kept-stage" || exit "$?"
      printf 'substituted\n' > "$safety_stage_path" || exit "$?"
      ;;
    cleanup-primary)
      chmod 500 -- "$root" || exit "$?"
      exit 42
      ;;
    moved-parent)
      mv -- "$root" "$case_dir/moved" || exit "$?"
      mkdir -- "$root" || exit "$?"
      ;;
    trace|file-*|link-*|parent-*|after-*)
      # Called by safety_publish_new in the sourced library.
      # shellcheck disable=SC2329
      _safety_native() {
        local event=$1 fault
        if [[ $event == fsync ]]; then
          if [[ $2 == "$safety_stage_fd" ]]; then
            event='file'
          else
            event=parent
          fi
        fi
        printf '%s\n' "$event" >> "$case_dir/trace" || return "$?"
        fault=${scenario#"$event"-}
        if [[ $scenario != "$fault" ]]; then
          # Inject syscall errno inside the actual packaged native implementation.
          python3 -I - "$fault" "$native" "$@" <<'PY'
import errno
import os
import runpy
import sys

_, fault, script, operation, *operands = sys.argv

def fail(*args, **kwargs):
    number = getattr(errno, fault)
    raise OSError(number, os.strerror(number))

setattr(os, operation, fail)
sys.argv = [script, operation, *operands]
runpy.run_path(script, run_name="__main__")
PY
          return "$?"
        fi
        python3 -I "$native" "$@" || return "$?"
        if [[ $event == link && $scenario == after-link-signal ]]; then
          kill -TERM "$BASHPID"
        elif [[ $scenario == "after-$event-move" ]]; then
          mv -- "$root" "$case_dir/moved" || return "$?"
          mkdir -- "$root" || return "$?"
        fi
      }
      ;;
  esac
  safety_publish_new || exit "$?"
  if [[ $scenario == cleanup-durable ]]; then
    entry "$root/archive" > "$case_dir/durable-entry" || exit "$?"
    chmod 500 -- "$root" || exit "$?"
  fi
)

lock_only() (
  safety_lock "$1"
)

stage_only() (
  safety_lock "$root" || exit "$?"
  safety_stage "$1"
)

new_case INTENT-01
expect_status 64 Denied safety_publish_new
for bad in '' /absolute '..' . ../archive other/archive .safety.lock .safety-stage.reserved; do
  expect_status 64 Denied stage_only "$bad"
done
unlink "$root/.safety.lock"
expect_status 64 Denied lock_only "$root"
[[ ! -e $root/.safety.lock ]] || fail 'library provisioned missing lock'
ln -s unrelated "$root/.safety.lock"
expect_status 64 Denied lock_only "$root"
[[ $(<"$root/unrelated") == unrelated ]] || fail 'lock symlink target changed'
expect_stages 0
expect_no_final
echo 'PASS INTENT-01 (invalid operands and lock provisioning)'

new_case BOUNDARY-01
ln -s "$root" "$case_dir/alias"
ln -s "$case_dir" "$fixture/alias-parent"
for bad in "${root#/}" "$case_dir/../BOUNDARY-01/root" "$case_dir/alias" "$fixture/alias-parent/root" "$root/unrelated"; do
  expect_status 69 Unsupported lock_only "$bad"
done
chmod 720 -- "$root"
expect_status 69 Unsupported lock_only "$root"
chmod 700 -- "$root"
expect_status 69 'Unsupported: root or stage changed' attempt moved-parent
expect_no_final
expect_stages 0
root=$case_dir/moved
expect_no_final
expect_stages 1
echo 'PASS BOUNDARY-01 (pathname checks and observed parent move)'

# Delay the actual canonicalization helper after its output, at the cleanup
# boundary. The operation must release the lock before returning to its caller.
new_case LOCK-02
(
  realpath_bin=${3:-$(command -v realpath)}
  printf '#!%s\n' "$BASH" > "$case_dir/slow-realpath"
  cat >> "$case_dir/slow-realpath" <<'SLOW_REALPATH'
set -eu
"$SAFETY_TEST_REALPATH" "$@" || exit "$?"
if [[ -f $SAFETY_TEST_TRACE ]] && grep -qx link "$SAFETY_TEST_TRACE"; then
  sleep 2
fi
SLOW_REALPATH
  chmod +x "$case_dir/slow-realpath"
  export SAFETY_TEST_REALPATH="$realpath_bin" SAFETY_TEST_TRACE="$case_dir/trace"
  sed "s|$realpath_bin|$case_dir/slow-realpath|g" "$library" > "$case_dir/instrumented.sh"
  [[ $(<"$case_dir/instrumented.sh") == *"$case_dir/slow-realpath"* ]] || fail 'realpath fault injection not installed'
  # shellcheck disable=SC1090,SC1091
  source "$case_dir/instrumented.sh"
  printf 'original\n' > "$root/archive"
  expect_status 73 'Conflict: link:' attempt link-EEXIST
  expect_status 0 '' flock --exclusive --nonblock --conflict-exit-code 73 "$root/.safety.lock" true
  [[ $(<"$root/archive") == original ]] || fail 'existing final changed'
  expect_stages 0
)
echo 'PASS LOCK-02 (operation completion releases helper-inherited lock)'

new_case BOUNDARY-02
root="$case_dir/"$'root\n'
mkdir -m 700 -- "$root"
touch "$root/.safety.lock"
expect_status 0 '' lock_only "$root"
expect_status 69 Unsupported lock_only "$root"$'\n'
echo 'PASS BOUNDARY-02 (canonical pathname with trailing newline)'

new_case PUBLISH-01-success
: > "$case_dir/stderr"
umask 777
expect_status 0 '' attempt
umask 022
expect_final
expect_stages 0
(( $(stat -c %h -- "$root/archive") == 1 )) || fail 'expected a single published link'

for kind in regular symlink dangling directory-link directory; do
  new_case "PUBLISH-01-$kind"
  mkdir "$root/referent"
  printf 'original\n' > "$root/referent/kept"
  referent=$(entry "$root/referent/kept")
  case $kind in
    regular)
      cp -- "$root/referent/kept" "$root/archive"
      chmod 640 -- "$root/archive"
      ;;
    symlink) ln -s referent/kept "$root/archive" ;;
    dangling) ln -s absent "$root/archive" ;;
    directory-link) ln -s referent "$root/archive" ;;
    directory)
      mkdir "$root/archive"
      cp -- "$root/referent/kept" "$root/archive/kept"
      directory_child=$(entry "$root/archive/kept")
      ;;
  esac
  before=$(entry "$root/archive")
  link_target=''
  if [[ -L $root/archive ]]; then
    link_target=$(readlink -- "$root/archive")
  fi
  for rerun in 1 2; do
    expect_status 73 'Conflict: link:' attempt
    [[ $(entry "$root/archive") == "$before" ]] || fail "existing inode or metadata changed on attempt $rerun"
    [[ $(entry "$root/referent/kept") == "$referent" && $(<"$root/referent/kept") == original ]] ||
      fail 'referent changed'
    if [[ -L $root/archive ]]; then
      [[ $(readlink -- "$root/archive") == "$link_target" ]] || fail 'symlink target changed'
    elif [[ -f $root/archive ]]; then
      [[ $(<"$root/archive") == original ]] || fail 'existing bytes changed'
    fi
    if [[ $kind == directory ]]; then
      children=("$root/archive"/* "$root/archive"/.[!.]* "$root/archive"/..?*)
      [[ ${#children[@]} == 1 && $(entry "$root/archive/kept") == "$directory_child" &&
        $(<"$root/archive/kept") == original ]] || fail 'collision added or changed a directory child'
    fi
    children=("$root/referent"/* "$root/referent"/.[!.]* "$root/referent"/..?*)
    (( ${#children[@]} == 1 )) || fail 'collision added a referent child'
    [[ ! -e $root/absent && ! -L $root/absent ]] || fail 'dangling link target created'
    expect_stages 0
  done
done
echo 'PASS PUBLISH-01 (verified 0600 final and native no-replace collisions)'

publish_fault() {
  local scenario=$1 status=$2 message=$3 trace=$4 visible=$5 stage_count=$6
  new_case "PUBLISH-02-$scenario"
  expect_status "$status" "$message" attempt "$scenario"
  if [[ -n $trace ]]; then
    [[ $(<"$case_dir/trace") == "$trace" ]] || fail 'unexpected fsync/link order'
  fi
  if [[ $visible == moved ]]; then
    expect_no_final
    root=$case_dir/moved
  fi
  if [[ $visible == no ]]; then
    expect_no_final
  else
    expect_final
  fi
  expect_stages "$stage_count"
  if [[ $visible != no && $stage_count == 1 ]]; then
    local stage=("$root"/.safety-stage.*)
    [[ ${stage[0]} -ef $root/archive ]] || fail 'retained stage and final have different inodes'
  fi
  [[ $(<"$root/unrelated") == unrelated ]] || fail 'unrelated file changed'
}

publish_fault trace 0 '' $'file\nlink\nparent' yes 0
publish_fault partial 42 '' '' no 0
publish_fault write-full 28 ENOSPC '' no 0
publish_fault invalid 43 '' '' no 0
publish_fault cancel 125 '' '' no 0
publish_fault signal 143 Interrupted '' no 0
publish_fault file-EIO 74 'IOError: fsync: errno' file no 0
publish_fault link-ENOSPC 74 'IOError: link: errno' $'file\nlink' no 0
publish_fault link-EOPNOTSUPP 69 'Unsupported: link: errno' $'file\nlink' no 0
publish_fault link-EXDEV 69 'Unsupported: link: errno' $'file\nlink' no 0
publish_fault link-EIO 75 OutcomeUnknown $'file\nlink' no 1
publish_fault parent-EIO 74 OutcomeUnknown $'file\nlink\nparent' yes 1
publish_fault after-link-signal 143 OutcomeUnknown $'file\nlink' yes 1
publish_fault after-link-move 75 OutcomeUnknown $'file\nlink' moved 1
publish_fault after-parent-move 75 OutcomeUnknown $'file\nlink\nparent' moved 1
echo 'PASS PUBLISH-02 (faults, exact flush order and uncertain publication)'

new_case LOCK-01
lock_entry=$(entry "$root/.safety.lock")
mkfifo -- "$case_dir/go"
exec {go_fd}<> "$case_dir/go"
(
  safety_lock "$root" || exit "$?"
  safety_stage archive || exit "$?"
  "$BASH" -eu -s -- "$case_dir" "$go_fd" "$safety_stage_fd" <<'WRITER' &
touch "$1/ready"
read -r -t 8 -u "$2" go
printf "finished writing\n" >&"$3"
touch "$1/done"
WRITER
  wait "$!"
) &
holder=$!
await_file() {
  local i
  for ((i = 0; i < 200; i++)); do
    [[ -f $1 ]] && return
    sleep 0.02
  done
  fail "writer marker ${1##*/} never appeared"
}
await_file "$case_dir/ready"
expect_status 73 'Conflict: operation lock' lock_only "$root"
kill -KILL "$holder"
expect_status 137 '' wait "$holder"
expect_status 73 'Conflict: operation lock' lock_only "$root"
printf 'go\n' >&"$go_fd"
await_file "$case_dir/done"
for ((i = 0; i < 200; i++)); do
  if lock_only "$root" 2>"$case_dir/stderr"; then
    break
  fi
  sleep 0.02
done
(( i < 200 )) || fail 'lock did not release after the inherited writer exited'
[[ $(entry "$root/.safety.lock") == "$lock_entry" ]] || fail 'lock entry changed'
expect_stages 1
stale=("$root"/.safety-stage.*)
[[ $(<"${stale[0]}") == 'finished writing' ]] || fail 'writer lost its stage descriptor'
echo 'PASS LOCK-01 (same inode, inherited writer and killed parent)'

# Rerun after SIGKILL in the same root with the actual leftover stage.
stale_entry=$(entry "${stale[0]}")
unrelated_entry=$(entry "$root/unrelated")
expect_status 0 '' attempt
expect_final
final_entry=$(entry "$root/archive")
expect_status 73 Conflict attempt
expect_final
expect_stages 1
[[ $(entry "${stale[0]}") == "$stale_entry" && $(<"${stale[0]}") == 'finished writing' &&
  $(entry "$root/archive") == "$final_entry" && $(entry "$root/unrelated") == "$unrelated_entry" ]] ||
  fail 'rerun changed a prior stage, final or unrelated file'

new_case OWNED-01
expect_status 69 'CleanupFailed' attempt stage-replaced
expect_no_final
expect_stages 1
replacement=("$root"/.safety-stage.*)
[[ $(<"${replacement[0]}") == substituted && $(<"$root/kept-stage") == 'complete payload' ]] ||
  fail 'cleanup changed the replacement or original inode'
echo 'PASS OWNED-01 (observed stage substitution is preserved)'

for scenario in cleanup-primary cleanup-durable; do
  new_case "RECOVERY-01-$scenario"
  before=$(entry "$root/unrelated")
  if [[ $scenario == cleanup-primary ]]; then
    expect_status 42 CleanupFailed attempt "$scenario"
    expect_no_final
  else
    expect_status 1 'CleanupFailed: final published and flushed' attempt "$scenario"
    expect_final
    [[ $(entry "$root/archive") == "$(<"$case_dir/durable-entry")" ]] || fail 'cleanup changed the confirmed final'
  fi
  chmod 700 -- "$root"
  expect_stages 1
  [[ $(entry "$root/unrelated") == "$before" && $(<"$root/unrelated") == unrelated ]] ||
    fail 'cleanup failure changed unrelated file'
done
echo 'PASS RECOVERY-01 (bounded cleanup, leftover and command status)'
