# Run via writeShellApplication (errexit, nounset and pipefail).
notify() {
  notify-send --app-name=richclip --expire-time=2500 "Clipboard history" "$1" >/dev/null 2>&1 || true
}

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  notify "No desktop runtime directory."
  exit 1
fi

# tofi and tofi-drun otherwise share tofi.lock. Use a picker-specific lock
# and let the application launcher retain its own existing lock policy.
exec 9>"$XDG_RUNTIME_DIR/richclip-picker.lock"
flock -n 9 || exit 0

recent=true
while :; do
  if [[ "$recent" == true ]]; then
    # One extra row tells us whether older entries exist.
    args=(--limit 129)
    deadline=2s
  else
    args=()
    deadline=10s
  fi
  if ! items="$(timeout --kill-after=1s "$deadline" richclip list --json "${args[@]}")"; then
    notify "Could not load history. Try again."
    exit 1
  fi
  if ! rows="$(printf '%s' "$items" | jq -r --argjson recent "$recent" '
    if type != "array" then error("expected history array") else . end
    | (if $recent then .[:128] else . end
       | .[]
       | .id + " " + ((.label // (.formats | map(.mime) | join(", ")))
                      | gsub("[[:cntrl:]]"; " ") | .[:160])),
      (if $recent and length > 128 then "__all__ Show all history" else empty end)
  ')"; then
    notify "Could not read history."
    exit 1
  fi
  if [[ -z "$rows" ]]; then
    notify "No saved clipboard history."
    exit 0
  fi
  if ! selection="$(printf '%s\n' "$rows" | tofi --multi-instance=true --history=false --require-match=true --prompt-text="Clipboard: ")"; then
    exit 0
  fi
  [[ -n "$selection" ]] || exit 0
  id="${selection%% *}"
  if [[ "$id" == __all__ && "$recent" == true ]]; then
    recent=false
    continue
  fi
  # Restore only a UUID from this immutable menu snapshot, never arbitrary text.
  if ! printf '%s\n' "$items" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
    notify "Clipboard entry not found."
    exit 1
  fi
  if ! timeout --kill-after=1s 5s richclip restore "$id"; then
    notify "Could not restore the clipboard entry."
    exit 1
  fi
  exit 0
done
