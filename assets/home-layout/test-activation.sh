#!/usr/bin/env bash
# Invoke only inside the disposable NixOS test machine.
set -euo pipefail
trap 'printf "Home activation fixture failed at line %s\n" "$LINENO" >&2' ERR

user=hfixture
home=/home/$user
profile=/etc/profiles/per-user/$user
base=$(readlink -f /run/current-system)
variants=$base/specialisation

as_user() {
  setpriv --reuid=1000 --regid="$(id -g "$user")" --init-groups \
    env -i HOME="$home" USER="$user" PATH=/run/current-system/sw/bin "$@"
}

app() {
  as_user bash -ec 'source "$1/etc/profile.d/hm-session-vars.sh"; shift; bash -c '"'"'exec "$@"'"'"' bash "$@"' \
    bash "$profile" "$profile/bin/fixture-app" "$@"
}

candidate() {
  "$variants/$1/bin/switch-to-configuration" test
}

test -f "$home/reached-initial"
test -L "$home/.codex/old-link"
as_user chmod 0710 "$home/.codex"
if candidate held > /tmp/cleanup.log 2>&1; then
  echo 'Home Manager cleanup admitted removal of a protected directory' >&2
  exit 1
fi
grep -F 'cleanup would remove a protected directory' /tmp/cleanup.log
test "$(readlink -f /run/current-system)" = "$base"
test -L "$home/.codex/old-link"
test "$(stat -c %a "$home/.codex")" = 710
test ! -e "$home/reached-held"
as_user bash -c 'printf "legacy-record\n" > "$HOME/.codex/record"'
inode=$(stat -c %i "$home/.codex/record")
test "$(app read)" = legacy-record

# An early switch failure must leave the profile, managed writes and app data alone.
for variant in intended backup forced; do
  if candidate "$variant" > "/tmp/$variant.log" 2>&1; then
    echo "$variant was admitted" >&2
    exit 1
  fi
  case "$variant" in
    intended) grep -F 'intended route requires a verified transfer' "/tmp/$variant.log" ;;
    backup|forced) grep -F 'Home Manager link would displace protected data' "/tmp/$variant.log" ;;
  esac
  test "$(readlink -f /run/current-system)" = "$base"
  test "$(app version)" = initial
  test ! -e "$home/reached-$variant"
  test ! -e "$home/.codex/record.hm-backup"
  test "$(stat -c %i "$home/.codex/record")" = "$inode"
done

as_user bash -c 'printf unmanaged > "$HOME/unrelated.txt"; printf incumbent > "$HOME/unrelated.txt.hm-backup"'
if candidate held > /tmp/unowned.log 2>&1; then
  echo 'Native Home Manager collision check accepted the occupied backup name' >&2
  exit 1
fi
grep -F 'would be clobbered by backing up' /tmp/unowned.log
test "$(cat "$home/unrelated.txt")" = unmanaged
test "$(cat "$home/unrelated.txt.hm-backup")" = incumbent
as_user mv "$home/unrelated.txt.hm-backup" "$home/saved-unrelated-backup"
candidate held
systemctl is-active home-manager-hfixture.service
test -f "$home/reached-held"
test "$(cat "$home/unrelated.txt.hm-backup")" = unmanaged
test ! -e "$home/.codex/old-link"
test "$(stat -c %a "$home/.codex")" = 710
test "$(app version)" = held
test "$(app read)" = legacy-record
test ! -e "$home/.local/share/codex/record"

unit_read() {
  systemctl start user@1000.service
  as_user env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start fixture-read.service
  tail -1 "$home/unit-read"
  systemctl stop user@1000.service
}
test "$(unit_read)" = legacy-record

wait_for_user_clear() {
  for attempt in $(seq 1 80); do
    if ! loginctl list-users --no-legend | awk '$1 == 1000 { found = 1 } END { exit !found }'; then
      return
    fi
    sleep 0.25
  done
  loginctl list-users >&2
  return 1
}
wait_for_user_clear

# The actual standalone HM pre-write path must reject the embedded backup
# policy too, even if NixOS's admission hook is bypassed.
forced=$(readlink -e "$variants/forced/etc/home-migration/$user")
if as_user env HOME_MANAGER_BACKUP_EXT=hm-backup "$forced/activate" --driver-version 1 > /tmp/hm-prewrite.log 2>&1; then
  exit 1
fi
grep -F 'Home Manager link would displace protected data' /tmp/hm-prewrite.log
test ! -e "$home/reached-forced"
test "$(stat -c %i "$home/.codex/record")" = "$inode"

# Prepare through the unactivated candidate's own runner.
runner="$variants/intended/etc/home-migration/$user/home-layout-migrate"
token=$(as_user "$runner" plan --group codex | jq -er .expect)
as_user "$runner" apply --group codex --offline --expect "$token"
as_user "$runner" apply --group codex --offline --expect "$token"
test "$(stat -c %i "$home/.local/share/codex/record")" = "$inode"
test ! -e "$home/.codex"
loginctl enable-linger "$user"
systemctl start user@1000.service
if candidate intended > /tmp/live.log 2>&1; then
  echo 'Route cutover accepted a running user manager' >&2
  exit 1
fi
grep -F 'exclude active sessions and writers before cutover' /tmp/live.log
loginctl disable-linger "$user"
if loginctl show-user "$user" >/dev/null 2>&1; then
  loginctl terminate-user "$user"
fi
wait_for_user_clear
candidate intended
systemctl is-active home-manager-hfixture.service
test -f "$home/reached-intended"
test -L "$home/.local/share/codex/new-link"
test "$(app version)" = intended
test "$(app read)" = legacy-record
app save reopened-record
test "$(app read | tail -1)" = reopened-record
test "$(unit_read)" = reopened-record
test ! -e "$home/.codex"

# Both candidate roots are empty. Only the installed intended route owns data.
installed=$(readlink -f /run/current-system)
loginctl enable-linger "$user"
systemctl start user@1000.service
if candidate redirected > /tmp/redirected-live.log 2>&1; then
  echo 'Changing the XDG base accepted a running user with incumbent data' >&2
  exit 1
fi
grep -F 'incumbent roots outside the candidate require assessment' /tmp/redirected-live.log
grep -F 'exclude active sessions and writers before cutover' /tmp/redirected-live.log
test "$(readlink -f /run/current-system)" = "$installed"
test "$(app version)" = intended
test ! -e "$home/reached-redirected"
test ! -e "$home/redirected-data"
test "$(app read | tail -1)" = reopened-record

loginctl disable-linger "$user"
if loginctl show-user "$user" >/dev/null 2>&1; then
  loginctl terminate-user "$user"
fi
wait_for_user_clear
if candidate redirected > /tmp/redirected-offline.log 2>&1; then
  echo 'Changing the XDG base accepted an empty target without a verified transfer' >&2
  exit 1
fi
grep -F 'intended route requires a verified transfer' /tmp/redirected-offline.log
test "$(readlink -f /run/current-system)" = "$installed"
test ! -e "$home/redirected-data"
test "$(app read | tail -1)" = reopened-record

# The native switch must be able to create a route-free account.
if id -u hnew >/dev/null 2>&1; then
  echo 'The route-free fixture account already exists' >&2
  exit 1
fi
candidate new-user
test "$(id -u hnew)" = 1001
test "$(cat /home/hnew/native-new-user.txt)" = "created by Home Manager"
test "$(app read | tail -1)" = reopened-record
installed=$(readlink -f /run/current-system)

# Candidate-only scoping would miss these affected incumbent rules.
for variant in remove-routes remove-account; do
  if candidate "$variant" > "/tmp/$variant.log" 2>&1; then
    echo "$variant ignored existing incumbent data" >&2
    exit 1
  fi
  grep -F 'removing a route with existing data' "/tmp/$variant.log"
  test "$(readlink -f /run/current-system)" = "$installed"
  test "$(app read | tail -1)" = reopened-record
done

mv "$home" "$home-unavailable"
if candidate remove-routes > /tmp/unavailable-home.log 2>&1; then
  echo 'The affected account was admitted while HOME was unavailable' >&2
  exit 1
fi
mv "$home-unavailable" "$home"
grep -F 'home migration stopped' /tmp/unavailable-home.log
test "$(readlink -f /run/current-system)" = "$installed"
test "$(app read | tail -1)" = reopened-record
