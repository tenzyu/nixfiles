# Only the restore command connects to the privileged socket.
notify() {
  notify-send --app-name=cclip --expire-time=2500 "Clipboard history" "$1" >/dev/null 2>&1 || true
}
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  notify "No desktop runtime directory."
  exit 1
fi
exec 9>"$XDG_RUNTIME_DIR/cclip-picker.lock"
flock -n 9 || exit 0
# cclip stores previews at capture time; no payload decoding, jq or all-MIME drain.
if ! rows="$(timeout --kill-after=1s 2s cclip list rowid,preview)"; then
  notify "Could not load history."
  exit 1
fi
if [[ -z "$rows" ]]; then
  notify "No saved clipboard history."
  exit 0
fi
selection="$(printf '%s\n' "$rows" | rofi -dmenu -replace -i -no-custom -format s -p Clipboard)" || exit 0
[[ -n "$selection" ]] || exit 0
id="${selection%%$'\t'*}"
if [[ ! "$id" =~ ^[1-9][0-9]*$ || "$selection" != *$'\t'* || $'\n'"$rows"$'\n' != *$'\n'"$selection"$'\n'* ]]; then
  notify "Clipboard entry not found."
  exit 1
fi
# cclip copy forks a selection owner. Close the picker lock FD so it is
# not inherited by that owner. CLI exit does not prove a successful paste.
if ! jay run-privileged cclip copy "$id" 9>&- >/dev/null; then
  notify "Could not restore the clipboard entry."
  exit 1
fi
