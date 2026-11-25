# No unattended GC, generation pruning or custom liveness classification.
if [[ ! -t 0 || ! -t 1 ]]; then
  echo 'GC requires an interactive local operator terminal.' >&2
  exit 2
fi
current=/run/current-system
booted=/run/booted-system
profile=/nix/var/nix/profiles/system
generation=$(consistent_generation "$current" "$booted" "$profile")
printf 'Local daemon GC only; preserving all roots. Generation: %s\n' "$generation"
df -h /nix/store
preview=$(mktemp)
trap 'rm -f -- "$preview"' EXIT
nix-store --store daemon --gc --print-dead > "$preview"
printf 'Native dead-path snapshot: %s entries (not a reclaimed-byte estimate).\n' "$(wc -l < "$preview")"
less -F "$preview"
printf 'Run sudo nix-store --store daemon --gc? Type GC exactly: '
read -r answer
[[ "$answer" == GC ]] || { echo 'Cancelled; no GC performed.'; exit 2; }
# Recheck after deliberation. Nix itself re-evaluates liveness at execution.
[[ "$(consistent_generation "$current" "$booted" "$profile")" == "$generation" ]] || {
  echo 'Generation changed; inspect again.' >&2; exit 1;
}
sudo -- /run/current-system/sw/bin/nix-store --store daemon --gc
df -h /nix/store
