#!/usr/bin/env bash
# shellcheck shell=bash
# jq programs intentionally use single-quoted strings with jq interpolation syntax.
# shellcheck disable=SC2016
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

q() { printf '%s' "$1" | jq -sR .; }

format_feature_rows() {
  awk -F '\t' '
    BEGIN { printf "  %-30s %-8s %-14s %s\n", "FEATURE", "STATUS", "ACTIVATION", "SOURCE" }
    { printf "  %-30s %-8s %-14s %s\n", $1, $2, $3, $4 }
  '
}

render_host_table() {
  local result_json=$1

  if [ "$scope" != "home" ]; then
    echo "SYSTEM FEATURES / $host"
    echo "$result_json" | jq -r '
      def loc($x):
        if ($x.source // null) == null then "-"
        elif ($x.line // null) == null then $x.source
        else $x.source + ":" + ($x.line | tostring) end;
      def firstActivation:
        if (.activations | length) == 0 then {kind: "-", source: null, line: null}
        else .activations[0] end;
      .system[] | [ .name, .status, (firstActivation.kind // "-"), loc(firstActivation) ] | @tsv
    ' | format_feature_rows
  fi

  if [ "$scope" != "system" ]; then
    echo "$result_json" | jq -r '
      def loc($x):
        if ($x.source // null) == null then "-"
        elif ($x.line // null) == null then $x.source
        else $x.source + ":" + ($x.line | tostring) end;
      def firstActivation:
        if (.activations | length) == 0 then {kind: "-", source: null, line: null}
        else .activations[0] end;
      if (.home | length) == 0 then
        ["__HEADER__", "(none enabled)"] | @tsv
      else
        .home
        | group_by(.user // "?")[]
        | (["__HEADER__", (.[0].user // "?")] | @tsv),
          (.[] | ["__ROW__", .name, .status, (firstActivation.kind // "-"), loc(firstActivation)] | @tsv)
      end
    ' | while IFS=$'\t' read -r tag a b c d; do
      case "$tag" in
        __HEADER__)
          echo
          echo "HOME FEATURES / ${a}@${host}"
          printf '  %-30s %-8s %-14s %s\n' "FEATURE" "STATUS" "ACTIVATION" "SOURCE"
          ;;
        __ROW__)
          printf '  %-30s %-8s %-14s %s\n' "$a" "$b" "$c" "$d"
          ;;
      esac
    done
  fi
}

render_feature_details() {
  local result_json=$1

  echo "$result_json" | jq -r '
    def loc($x):
      if ($x.source // null) == null then "-"
      elif ($x.line // null) == null then $x.source
      else $x.source + ":" + ($x.line | tostring) end;
    def records:
      if .scope == "all" then ([.system] + (.home // [])) else [.] end;
    records[]
    | (["FEATURE", .name, .scope, (.user // ""), .status] | @tsv),
      (["SECTION", "ACTIVATIONS"] | @tsv),
      (if (.activations | length) == 0
       then ["EMPTY"] | @tsv
       else (.activations[] | ["ACT", (.kind // "-"), (.option // "-"), loc(.), (.by // "")] | @tsv) end),
      (["SECTION", "IMPLEMENTATIONS"] | @tsv),
      (if (.implementations | length) == 0
       then ["EMPTY"] | @tsv
       else (.implementations[] | ["IMPL", (.moduleClass // "-"), (.optionPrefix // "-"), loc(.)] | @tsv) end),
      (["SECTION", "EFFECTS"] | @tsv),
      (if (.effects | length) == 0
       then ["EMPTY"] | @tsv
       else (.effects[] | ["EFF", (.kind // "-"), (.renderedValue // "-"), loc(.)] | @tsv) end)
  ' | awk -F '\t' '
    $1 == "FEATURE" {
      if (seen++) print "";
      title = "feature: " $2 "  scope: " $3;
      if ($4 != "") title = title "/" $4;
      title = title "  status: " $5;
      print title;
      next;
    }
    $1 == "SECTION" {
      print "";
      print $2;
      if ($2 == "ACTIVATIONS") printf "  %-14s %-54s %s\n", "KIND", "OPTION", "SOURCE";
      else if ($2 == "IMPLEMENTATIONS") printf "  %-14s %-54s %s\n", "CLASS", "MODULE", "SOURCE";
      else if ($2 == "EFFECTS") printf "  %-14s %-12s %s\n", "KIND", "VALUE", "SOURCE";
      next;
    }
    $1 == "EMPTY" { print "  -"; next; }
    $1 == "ACT" {
      extra = ($5 == "" ? "" : "  by " $5);
      opt = $3; if (length(opt) > 54) opt = substr(opt, 1, 51) "...";
      printf "  %-14s %-54s %s%s\n", $2, opt, $4, extra;
      next;
    }
    $1 == "IMPL" {
      opt = $3; if (length(opt) > 54) opt = substr(opt, 1, 51) "...";
      printf "  %-14s %-54s %s\n", $2, opt, $4; next;
    }
    $1 == "EFF" { printf "  %-14s %-12s %s\n", $2, $3, $4; next; }
  '
}

candidate_tsv() {
  local result_json=$1
  local filter

  if [ -n "$why" ]; then
    filter='
      .definitions[]?
      | select(.source != null)
      | ["definition", "why", "-", (.kind // "-"), (.path // "-"), .source, ((.line // 1) | tostring)]
      | @tsv
    '
  elif [ -n "$feature" ]; then
    case "$edit_target" in
      activation)
        filter='
          def records: if .scope == "all" then ([.system] + (.home // [])) else [.] end;
          records[] as $r
          | $r.activations[]?
          | select(.source != null)
          | ["activation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.kind // "-"), (.option // "-"), .source, ((.line // 1) | tostring)]
          | @tsv
        '
        ;;
      implementation)
        filter='
          def records: if .scope == "all" then ([.system] + (.home // [])) else [.] end;
          records[] as $r
          | $r.implementations[]?
          | select(.source != null)
          | ["implementation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.moduleClass // "-"), (.optionPrefix // "-"), .source, ((.line // 1) | tostring)]
          | @tsv
        '
        ;;
      *)
        filter='
          def records: if .scope == "all" then ([.system] + (.home // [])) else [.] end;
          records[] as $r
          | (
              $r.activations[]?
              | select(.source != null)
              | ["activation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.kind // "-"), (.option // "-"), .source, ((.line // 1) | tostring)]
            ),
            (
              $r.implementations[]?
              | select(.source != null)
              | ["implementation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.moduleClass // "-"), (.optionPrefix // "-"), .source, ((.line // 1) | tostring)]
            )
          | @tsv
        '
        ;;
    esac
  else
    case "$edit_target" in
      activation)
        filter='
          ((.system // []) + (.home // []))[] as $r
          | $r.activations[]?
          | select(.source != null)
          | ["activation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.kind // "-"), (.option // "-"), .source, ((.line // 1) | tostring)]
          | @tsv
        '
        ;;
      implementation)
        filter='
          ((.system // []) + (.home // []))[] as $r
          | $r.implementations[]?
          | select(.source != null)
          | ["implementation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.moduleClass // "-"), (.optionPrefix // "-"), .source, ((.line // 1) | tostring)]
          | @tsv
        '
        ;;
      *)
        filter='
          ((.system // []) + (.home // []))[] as $r
          | (
              $r.activations[]?
              | select(.source != null)
              | ["activation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.kind // "-"), (.option // "-"), .source, ((.line // 1) | tostring)]
            ),
            (
              $r.implementations[]?
              | select(.source != null)
              | ["implementation", ($r.scope + (if ($r.user // null) != null then "/" + $r.user else "" end)), $r.name, (.moduleClass // "-"), (.optionPrefix // "-"), .source, ((.line // 1) | tostring)]
            )
          | @tsv
        '
        ;;
    esac
  fi

  echo "$result_json" | jq -r "$filter" | awk -F '\t' '!seen[$0]++'
}

format_candidates() {
  awk -F '\t' '
    BEGIN { printf "%-15s %-14s %-30s %-16s %-58s %s\n", "TARGET", "SCOPE", "FEATURE", "KIND", "OPTION/MODULE", "SOURCE" }
    {
      feature = $3; if (length(feature) > 30) feature = substr(feature, 1, 27) "...";
      opt = $5; if (length(opt) > 58) opt = substr(opt, 1, 55) "...";
      printf "%-15s %-14s %-30s %-16s %-58s %s:%s\n", $1, $2, feature, $4, opt, $6, $7
    }
  '
}

repo=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo" ]; then
  repo=$(nix eval --raw ".#nixosConfigurations.${host}.config.local.context.flakePath" 2>/dev/null || true)
fi
if [ -z "$repo" ]; then
  echo "feature-trace: cannot determine repo path" >&2
  exit 1
fi

repo_q=$(q "$repo")

if [ "$scope" = "home" ] && [ -z "$user" ] && [ -z "$why" ]; then
  users_tmp=$(mktemp)
  host_q=$(q "$host")
  cat > "$users_tmp" <<NIX
let
  repo = $repo_q;
  host = builtins.fromJSON $host_q;
  flake = builtins.getFlake (toString repo);
in
  builtins.attrNames (
    builtins.filterAttrs (_: u: u.enable or true) (builtins.getAttr host flake.nixosConfigurations).config.local.users
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
    def loc($x):
      if ($x.source // null) == null then "-"
      elif ($x.line // null) == null then $x.source
      else $x.source + ":" + ($x.line | tostring) end;
    "option: " + .path,
    "effective: " + .effective,
    "",
    "DEFINITIONS",
    (if (.definitions | length) == 0 then "  -" else (.definitions[] | "  " + (.kind // "-") + "  " + (.renderedValue // "-") + "  " + loc(.)) end)
  ' | head -200
elif [ -n "$feature" ]; then
  render_feature_details "$result" | head -240
else
  render_host_table "$result" | head -300
fi

if [ "$edit" = true ]; then
  candidates=$(candidate_tsv "$result")
  n=$(echo "$candidates" | grep -c . || true)
  if [ "$n" -eq 0 ]; then
    echo "feature-trace: no source file to edit" >&2
    exit 1
  elif [ "$n" -eq 1 ]; then
    IFS=$'\t' read -r _target _scope _feature _kind _option file line <<< "$candidates"
    loc="${file}:${line:-1}"
  else
    if command -v fzf >/dev/null 2>&1; then
      pick=$(printf '%s\n' "$candidates" | format_candidates | fzf --header-lines=1 --prompt "feature-trace: select source > " || true)
      [ -n "$pick" ] || { echo "feature-trace: no selection" >&2; exit 1; }
      loc=$(printf '%s' "$pick" | awk '{print $NF}')
    else
      echo "feature-trace: multiple candidate source files (no fzf available):" >&2
      printf '%s\n' "$candidates" | format_candidates >&2
      exit 1
    fi
  fi

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
