#!/usr/bin/env bash
set -euo pipefail

host=""
user=""
scope="all"
feature=""
why=""
edit=false
edit_target=""
json=false

usage() {
cat <<'USAGE'
Usage: feature-trace [OPTIONS]

Required:
  --host HOST

Selectors:
  --user USER
  --scope system|home|all
  --feature FEATURE
  --why OPTION_PATH

Output/edit:
  --json
  --edit
  --edit-activation
  --edit-config, --edit-implementation
  --no-color
  -h, --help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --user) user="$2"; shift 2 ;;
    --scope) scope="$2"; shift 2 ;;
    --feature) feature="$2"; shift 2 ;;
    --why) why="$2"; shift 2 ;;
    --edit) edit=true; shift ;;
    --edit-activation) edit=true; edit_target="activation"; shift ;;
    --edit-config|--edit-implementation) edit=true; edit_target="implementation"; shift ;;
    --json) json=true; shift ;;
    --no-color) shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "feature-trace: unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [ -z "$host" ]; then
  echo "feature-trace: --host is required" >&2
  usage >&2
  exit 64
fi

case "$scope" in
  system|home|all) ;;
  *) echo "feature-trace: --scope must be system, home, or all (got: $scope)" >&2; exit 64 ;;
esac

repo=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo" ]; then
  repo=$(nix eval --raw ".#nixosConfigurations.${host}.config.local.context.flakePath" 2>/dev/null || true)
fi
if [ -z "$repo" ]; then
  echo "feature-trace: cannot determine repo path" >&2
  exit 1
fi

q() { printf '%s' "$1" | jq -sR .; }
repo_q=$(q "$repo")

if [ "$scope" = "home" ] && [ -z "$user" ] && [ -z "$why" ]; then
  users_tmp=$(mktemp)
  cat > "$users_tmp" <<NIX
let
  repo = $repo_q;
  flake = builtins.getFlake (toString repo);
in
  builtins.attrNames (
    builtins.filterAttrs (_: u: u.enable or true) flake.nixosConfigurations.${host}.config.local.users
  )
NIX
  users_json=$(nix eval --json --impure --file "$users_tmp" 2>/dev/null || echo "[]")
  rm -f "$users_tmp"
  n_users=$(echo "$users_json" | jq 'length')
  if [ "$n_users" -gt 1 ]; then
    echo "feature-trace: --scope home requires --user when multiple users exist on '$host'" >&2
    echo "  enabled users: $(echo "$users_json" | jq -r '. | join(", ")')" >&2
    exit 64
  fi
  if [ "$n_users" -eq 1 ]; then
    user=$(echo "$users_json" | jq -r '.[0]')
  fi
fi

args_json=$(jq -n \
  --arg host "$host" \
  --arg user "$user" \
  --arg scope "$scope" \
  --arg feature "$feature" \
  --arg why "$why" \
  '{host: $host, user: $user, scope: $scope, feature: $feature, why: $why}')
args_q=$(printf '%s' "$args_json" | jq -sR .)

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" <<NIX
let
  repo = $repo_q;
  flake = builtins.getFlake (toString repo);
  core = import (repo + "/modules/10-framework/tools/feature-trace.nix") {
    lib = flake.inputs.nixpkgs.lib;
  };
  args = builtins.fromJSON $args_q;
  base = { inherit repo flake; host = args.host; };
  withUser = if args.user != "" then base // { user = args.user; } else base;
  fullArgs = withUser // { scope = args.scope; };
in
  if args.why != "" then core.traceWhy (base // { option = args.why; } // (if args.user != "" then { user = args.user; } else {}))
  else if args.feature != "" then core.traceFeature (fullArgs // { feature = args.feature; })
  else core.traceHost fullArgs
NIX

if ! result=$(nix eval --json --impure --file "$tmp" 2>/dev/null); then
  echo "feature-trace: nix eval failed" >&2
  nix eval --json --impure --file "$tmp" >&2 || true
  exit 1
fi

if [ "$json" = true ]; then
  echo "$result" | jq .
elif [ -n "$why" ]; then
  echo "$result" | jq -r '
    def loc: if .line == null then .source else .source + ":" + (.line|tostring) end;
    "option: " + .path,
    "effective: " + .effective,
    "definitions:",
    (if (.definitions | length) == 0 then "  -" else (.definitions[] | "  " + loc + "  " + .renderedValue + "  " + .kind) end)
  ' | head -200
elif [ -n "$feature" ]; then
  if echo "$result" | jq -e '.scope == "all"' >/dev/null; then
    echo "$result" | jq -r '
      def loc: if .line == null then .source else .source + ":" + (.line|tostring) end;
      def render:
        "feature: " + .name + "  scope: " + .scope + "  status: " + .status,
        "",
        "activated by:",
        (if (.activations | length) == 0 then "  -" else (.activations[] | "  " + .kind + "  " + (.option // "-") + "  " + loc + (if (.by // null) then "  by " + .by else "" end)) end),
        "",
        "implemented by:",
        (if (.implementations | length) == 0 then "  -" else (.implementations[] | "  " + .optionPrefix + "  " + loc) end),
        "",
        "effects:",
        (if (.effects | length) == 0 then "  -" else (.effects[] | "  " + loc + "  " + .renderedValue + "  " + .kind) end);
      .system | render
    ' | head -200
    if echo "$result" | jq -e '(.home | length) > 0' >/dev/null; then
      echo
      echo "$result" | jq -r '
        def loc: if .line == null then .source else .source + ":" + (.line|tostring) end;
        def render:
          "feature: " + .name + "  scope: " + .scope + "  status: " + .status,
          "",
          "activated by:",
          (if (.activations | length) == 0 then "  -" else (.activations[] | "  " + .kind + "  " + (.option // "-") + "  " + loc + (if (.by // null) then "  by " + .by else "" end)) end),
          "",
          "implemented by:",
          (if (.implementations | length) == 0 then "  -" else (.implementations[] | "  " + .optionPrefix + "  " + loc) end),
          "",
          "effects:",
          (if (.effects | length) == 0 then "  -" else (.effects[] | "  " + loc + "  " + .renderedValue + "  " + .kind) end);
        .home[] | render
      ' | head -200
    fi
  else
    echo "$result" | jq -r '
      def loc: if .line == null then .source else .source + ":" + (.line|tostring) end;
      "feature: " + .name + "  scope: " + .scope + "  status: " + .status,
      "",
      "activated by:",
      (if (.activations | length) == 0 then "  -" else (.activations[] | "  " + .kind + "  " + (.option // "-") + "  " + loc + (if (.by // null) then "  by " + .by else "" end)) end),
      "",
      "implemented by:",
      (if (.implementations | length) == 0 then "  -" else (.implementations[] | "  " + .optionPrefix + "  " + loc) end),
      "",
      "effects:",
      (if (.effects | length) == 0 then "  -" else (.effects[] | "  " + loc + "  " + .renderedValue + "  " + .kind) end)
    ' | head -200
  fi
else
  echo "$result" | jq -r --arg scope "$scope" '
    def loc: if .line == null then .source else .source + ":" + (.line|tostring) end;
    def activationSummary:
      if (.activations | length) == 0 then "-"
      else (.activations[0] | (.kind + " " + loc)) end;
    def sysHeader: if $scope == "home" then empty else "SYSTEM FEATURES / " + .host end;
    def sysRows: if $scope == "home" then empty else .system[] | .name + "\t" + .status + "\t" + activationSummary end;
    def homeHeader:
      if $scope == "system" then empty
      elif (.home | length) > 0 then "HOME FEATURES / " + (.home[0].user // "?") + "@" + .host
      else "HOME FEATURES / (none enabled)@" + .host end;
    def homeRows: if $scope == "system" then empty else .home[] | .name + "\t" + .status + "\t" + activationSummary end;
    [sysHeader, sysRows, homeHeader, homeRows] | .[] | select(. != null and . != "")
  '
fi

if [ "$edit" = true ]; then
  if [ -n "$why" ]; then
    jq_filter='.definitions[]? | select(.source != null) | "definition\t\(.source):\(.line // 1)"'
  elif [ -n "$feature" ]; then
    case "$edit_target" in
      activation) jq_filter='if .scope == "all" then ([.system] + (.home // []))[] else . end | .activations[]? | select(.source != null) | "activation\t\(.source):\(.line // 1)"' ;;
      implementation) jq_filter='if .scope == "all" then ([.system] + (.home // []))[] else . end | .implementations[]? | select(.source != null) | "implementation\t\(.source):\(.line // 1)"' ;;
      *) jq_filter='if .scope == "all" then ([.system] + (.home // []))[] else . end | ((.activations[]? | select(.source != null) | "activation\t\(.source):\(.line // 1)"), (.implementations[]? | select(.source != null) | "implementation\t\(.source):\(.line // 1)"))' ;;
    esac
  else
    jq_filter='((.system // []) + (.home // []))[] | ((.activations[]? | select(.source != null) | "activation\t\(.source):\(.line // 1)"), (.implementations[]? | select(.source != null) | "implementation\t\(.source):\(.line // 1)"))'
  fi

  candidates=$(echo "$result" | jq -r "$jq_filter" | awk '!seen[$0]++')
  n=$(echo "$candidates" | grep -c . || true)
  if [ "$n" -eq 0 ]; then
    echo "feature-trace: no source file to edit" >&2
    exit 1
  elif [ "$n" -eq 1 ]; then
    pick="$candidates"
  else
    if command -v fzf >/dev/null 2>&1; then
      pick=$(printf '%s\n' "$candidates" | fzf --prompt "feature-trace: select source > " || true)
      [ -n "$pick" ] || { echo "feature-trace: no selection" >&2; exit 1; }
    else
      echo "feature-trace: multiple candidate source files (no fzf available):" >&2
      echo "$candidates" | while IFS= read -r line; do echo "  $line" >&2; done
      exit 1
    fi
  fi

  loc=${pick#*$'\t'}
  file=${loc%:*}
  line=${loc##*:}
  [ -n "$line" ] || line=1
  abs_file="$repo/$file"
  if [ ! -f "$abs_file" ]; then
    echo "feature-trace: source file not found: $abs_file" >&2
    exit 1
  fi
  exec "${EDITOR:-vi}" "+$line" "$abs_file"
fi
