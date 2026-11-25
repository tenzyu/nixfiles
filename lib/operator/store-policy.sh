# Supporting subdomain: operator admission, never store reachability.
# All three symlinks must exist and identify the same generation.
consistent_generation() {
  local current booted profile
  current=$(readlink -e -- "$1") || return 1
  booted=$(readlink -e -- "$2") || return 1
  profile=$(readlink -e -- "$3") || return 1
  if [[ "$current" == "$booted" && "$current" == "$profile" ]]; then
    printf '%s\n' "$current"
    return 0
  fi
  printf 'Refusing GC: current, booted and profile generations disagree.\n' >&2
  return 1
}
