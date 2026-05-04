autoload -Uz select-word-style
select-word-style bash

function backward-kill-smart-word() {
  local left="$LBUFFER"
  local match

  if [[ -z "$left" ]]; then
    zle backward-kill-word
    return
  fi

  if [[ "$left" =~ [[:space:]]+$ ]]; then
    match="$MATCH"
  elif [[ "$left" =~ [[:alnum:]_./-]+$ ]]; then
    match="$MATCH"
  elif [[ "$left" =~ [ぁ-んァ-ンー一-龥々]+$ ]]; then
    match="$MATCH"
  elif [[ "$left" =~ [[:punct:]]+$ ]]; then
    match="$MATCH"
  else
    match="${left[-1,-1]}"
  fi

  LBUFFER="${left[1,$(( ${#left} - ${#match} ))]}"
}

if [[ -o interactive ]]; then
  zle -N backward-kill-smart-word
  bindkey '^W' backward-kill-smart-word
fi

function tm() {
  local session="${1:-main}"
  tmux new -As "$session"
}

function gdiffstaged() {
  git diff --cached --stat --minimal
  echo
  git diff --cached --minimal
}

function gcai() {
  emulate -L zsh

  local agent="codex"
  local message
  local err
  local status

  while (( $# > 0 )); do
    case "$1" in
      codex|--codex)
        agent="codex"
        shift
        ;;

      gemini|--gemini|-g)
        agent="gemini"
        shift
        ;;

      --agent)
        shift
        if (( $# == 0 )); then
          print -u2 "Missing value for --agent"
          return 1
        fi

        case "$1" in
          codex|gemini)
            agent="$1"
            shift
            ;;
          *)
            print -u2 "Unknown agent: $1"
            return 1
            ;;
        esac
        ;;

      -h|--help)
        print "Usage: gcai [codex|gemini|--codex|--gemini|-g|--agent codex|--agent gemini]"
        return 0
        ;;

      *)
        print -u2 "Unknown argument: $1"
        return 1
        ;;
    esac
  done

  if git diff --cached --quiet; then
    print -u2 "No staged changes. Stage files before generating a commit message."
    return 1
  fi

  err="$(mktemp "${TMPDIR:-/tmp}/gcai-stderr.XXXXXX")" || return

  case "$agent" in
    codex)
      message="$(
        {
          cat <<'EOF'
Write a single git commit subject line for the staged changes.
Use conventional commits style when it fits naturally.
Return only the subject line.
Keep it under 72 characters.
EOF
          echo
          echo "Staged diff summary:"
          git diff --cached --stat --minimal
          echo
          echo "Staged diff:"
          git diff --cached --minimal
        } | codex exec --skip-git-repo-check - 2>"$err"
      )"
      status=$?
      ;;

    gemini)
      message="$(
        {
          cat <<'EOF'
Write a single git commit subject line for the staged changes.
Use conventional commits style when it fits naturally.
Return only the subject line.
Keep it under 72 characters.
Do not inspect files.
Do not use tools.
EOF
          echo
          echo "Staged diff summary:"
          git diff --cached --stat --minimal
          echo
          echo "Staged diff:"
          git diff --cached --minimal
        } | gemini \
          --skip-trust \
          --extensions none \
          -p "Generate the commit subject from the input above." \
          2>"$err"
      )"
      status=$?
      ;;
  esac

  if (( status != 0 )); then
    if (( status == 130 || status == 143 )); then
      rm -f "$err"
      return "$status"
    fi

    if [[ -s "$err" ]]; then
      cat "$err" >&2
    else
      print -u2 "AI command failed with status $status."
    fi

    rm -f "$err"
    return "$status"
  fi

  rm -f "$err"

  message="$(
    print -r -- "$message" \
      | sed -n '1p' \
      | sed 's/^["'\''`]*//; s/["'\''`]*$//'
  )"

  if [[ -z "$message" ]]; then
    print -u2 "AI returned an empty commit message."
    return 1
  fi

  print -r -- "$message"
  git commit -e -F <(print -r -- "$message")
}
