# shellcheck shell=bash

if (( EUID != archiveUid )) || [[ $(id -g) != "$archiveGid" ]]; then
  echo 'Denied: archive writer requires the configured game UID and GID' >&2
  exit 64
fi

readonly action=$1 leaf=$2 lifecycle_fd=$3 lifecycle_inode=$4
if [[ $(stat -Lc '%d:%i' -- "/proc/self/fd/$lifecycle_fd") != "$lifecycle_inode" ]]; then
  echo 'Unsupported: host lifecycle descriptor did not survive the archive UID transition' >&2
  exit 69
fi
# shellcheck disable=SC1090,SC1091
source "$safety"
finish_archive() {
  local status=$1
  if [[ $action == archive ]] && (( status == 73 || publication_attempted == 0 )); then
    printf 'not-published\n'
  fi
  safety_finish "$status"
}
publication_attempted=0
trap 'finish_archive "$?"' EXIT
trap 'echo "Interrupted: archive writer (TERM)" >&2; exit 143' TERM
trap 'echo "Interrupted: archive writer (INT)" >&2; exit 130' INT
trap 'echo "Interrupted: archive writer (HUP)" >&2; exit 129' HUP
umask 077
export LC_ALL=C

if [[ $boundary == / ]]; then
  case $(stat -fLc '%T' -- "$backupsDir") in
    ext2/ext3|btrfs|xfs|zfs|f2fs) ;;
    *) echo 'Unsupported: archive destination needs a local persistent filesystem' >&2; exit 69 ;;
  esac
fi
"$filesystem" -I "$checks" prepare "$boundary" "$sourceDir" "$backupsDir"
safety_lock "$backupsDir"
if [[ -e $backupsDir/$leaf || -L $backupsDir/$leaf ]]; then
  printf 'Conflict: archive leaf already exists: %s/%s\n' "$backupsDir" "$leaf" >&2
  exit 73
fi
case "$action" in
  preflight) exit 0 ;;
  archive) ;;
  *) exit 64 ;;
esac

safety_stage "$leaf"
# These handles are assigned by safety_stage in the sourced library.
# shellcheck disable=SC2154
stage_fd=$safety_stage_fd stage_path=$safety_stage_path
"$producer" --create --gzip --file=- --directory="${sourceDir%/*}" -- "${sourceDir##*/}" >&"$stage_fd"
"$producer_gzip" --test -- "$stage_path"
tar --list --gzip --file="$stage_path" >/dev/null
"$filesystem" -I "$checks" validate "$stage_path"
publication_attempted=1
safety_publish_new
printf 'published\n'
