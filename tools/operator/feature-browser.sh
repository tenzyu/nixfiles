# UI port: fzf owns search/selection, bat preview, rg line candidates.
# The supporting Nix projection owns all source metadata.
rows=$(nix eval --no-update-lock-file --json .#operator.features)
selection=$(jq -r 'to_entries[] | [.key, .value.configuration,
  (.value.user // "-"), .value.scope, .value.feature,
  (if .value.enabled then "enabled" else "disabled" end)] | @tsv' <<< "$rows" |
  fzf --no-multi --delimiter=$'\t' --with-nth=2.. \
    --header='HOST/CONFIG  USER  SCOPE  FEATURE  EFFECTIVE' --prompt='Feature> ')
index=${selection%%$'\t'*}
row=$(jq -ce --argjson index "$index" '.[$index]' <<< "$rows")
feature=$(jq -er '.feature' <<< "$row")
class=$(jq -er '.moduleClass' <<< "$row")
# Quote each attribute path segment (Nix CLI attribute path syntax).
selector=$(jq -r '
  (if .scope == "system" then ["nixos", .configuration, "system", .feature]
   elif .scope == "home" then ["nixos", .configuration, "home", .user, .feature]
   else ["standalone", .configuration, .feature] end)
  | map(@json) | join(".")' <<< "$row")
native=$(nix eval --no-update-lock-file --json ".#operator.origins.$selector")
printf 'Native surviving definition locations (including synthetic/default origins):\n' >&2
jq -r '.locations[]' <<< "$native" >&2
root=$(realpath -e -- "$(git rev-parse --show-toplevel)")
repo_source() {
  local absolute
  git --literal-pathspecs ls-files --error-unmatch -- "$1" >/dev/null 2>&1 || return 1
  absolute=$(realpath -e -- "$1") || return 1
  [[ "$absolute" == "$root/"* && -f "$absolute" ]]
}
sources=$(jq -r --argjson native "$native" '
  (.sources + {effective: $native.files}) | to_entries[]
  | .key as $kind | .value[] | [$kind, .] | @tsv' <<< "$row")
# Reject external and untracked candidates before handing them to the preview.
sources=$(while IFS=
  echo 'No repository-owned source location; inspect native metadata above.' >&2
  exit 1
fi
# shellcheck disable=SC2016
source_row=$(fzf --no-multi --select-1 --delimiter=$'\t' --prompt='Source> ' \
  --header='selection / registration (conditional) / effective' \
  --preview='bat --style=numbers --color=always --line-range :200 -- {2}' <<< "$sources")
file=${source_row#*$'\t'}
# Recheck the selected path after interactive browsing.
repo_source "$file" || exit 1
# Native metadata is file-granular. Search only that exact file, with an
# honest fallback to its first line when the registration uses other syntax.
matches=
status=0
matches=$(rg -n --no-heading --no-filename --color never -F \
  -e "$feature.enable" -e "\"$feature\".enable" \
  -e "modules.$class.$feature" -e "modules.$class.\"$feature\"" -- "$file") || status=$?
if (( status > 1 )); then exit "$status"; fi
line=1
if [[ -n "$matches" ]]; then
  export NIXFILES_SOURCE_FILE="$file"
  # shellcheck disable=SC2016
  match=$(fzf --no-multi --select-1 --delimiter=: --prompt='Line> ' \
    --preview='bat --color=always --highlight-line {1} -- "$NIXFILES_SOURCE_FILE"' <<< "$matches")
  line=${match%%:*}
fi
editor=${NIXFILES_EDITOR:-${VISUAL:-${EDITOR:-nvim}}}
if ! command -v "$editor" >/dev/null; then
  printf 'Source: %s:%s\nSet NIXFILES_EDITOR to a vi-compatible editor executable.\n' "$file" "$line" >&2
  exit 1
fi
exec "$editor" "+$line" -- "$file"
\t' read -r kind file; do
  if repo_source "$file"; then
    printf '%s\t%s\n' "$kind" "$file"
  fi
done <<< "$sources")
if [[ -z "$sources" ]]; then
  echo 'No repository-owned source location; inspect native metadata above.' >&2
  exit 1
fi
# shellcheck disable=SC2016
source_row=$(fzf --no-multi --select-1 --delimiter=$'\t' --prompt='Source> ' \
  --header='selection / registration (conditional) / effective' \
  --preview='bat --style=numbers --color=always --line-range :200 -- {2}' <<< "$sources")
file=${source_row#*$'\t'}
# Recheck the selected path after interactive browsing.
repo_source "$file" || exit 1
# Native metadata is file-granular. Search only that exact file, with an
# honest fallback to its first line when the registration uses other syntax.
matches=
status=0
matches=$(rg -n --no-heading --no-filename --color never -F \
  -e "$feature.enable" -e "\"$feature\".enable" \
  -e "modules.$class.$feature" -e "modules.$class.\"$feature\"" -- "$file") || status=$?
if (( status > 1 )); then exit "$status"; fi
line=1
if [[ -n "$matches" ]]; then
  export NIXFILES_SOURCE_FILE="$file"
  # shellcheck disable=SC2016
  match=$(fzf --no-multi --select-1 --delimiter=: --prompt='Line> ' \
    --preview='bat --color=always --highlight-line {1} -- "$NIXFILES_SOURCE_FILE"' <<< "$matches")
  line=${match%%:*}
fi
editor=${NIXFILES_EDITOR:-${VISUAL:-${EDITOR:-nvim}}}
if ! command -v "$editor" >/dev/null; then
  printf 'Source: %s:%s\nSet NIXFILES_EDITOR to a vi-compatible editor executable.\n' "$file" "$line" >&2
  exit 1
fi
exec "$editor" "+$line" -- "$file"
