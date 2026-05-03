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

function gmsg() {
  if git diff --cached --quiet; then
    echo "No staged changes. Stage files before generating a commit message." >&2
    return 1
  fi

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
  } | codex exec --skip-git-repo-check -
}

function gcai() {
  local message

  message="$(gmsg)" || return
  echo "$message"
  git commit -m "$message"
}
