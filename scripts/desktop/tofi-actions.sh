# Static, allowlisted actions. Only the explicit run mode interprets shell syntax.
case "${1:-}" in
  run)
    command="$(tofi-run --require-match=false --prompt-text='Run: ')" || exit 0
    [[ -n "$command" ]] || exit 0
    exec @SHELL@ -c "$command"
    ;;
  custom)
    selection="$(printf '%s\n' 'Nixfiles shell' 'Nixfiles GitUI' 'System monitor' 'Disk usage' |
      tofi --history=false --require-match=true --prompt-text='Commands: ')" || exit 0
    case "$selection" in
      'Nixfiles shell') exec alacritty --working-directory "$HOME/.nixfiles" ;;
      'Nixfiles GitUI') exec alacritty --working-directory "$HOME/.nixfiles" -e gitui ;;
      'System monitor') exec alacritty -e btop ;;
      'Disk usage') exec alacritty -e dua i ;;
      *) exit 0 ;;
    esac
    ;;
  desktop)
    selection="$(printf '%s\n' 'Jay control center' 'Open Jay config directory' 'Toggle input method' |
      tofi --history=false --require-match=true --prompt-text='Desktop: ')" || exit 0
    case "$selection" in
      'Jay control center') exec jay control-center ;;
      'Open Jay config directory') exec jay config open-dir ;;
      'Toggle input method') exec fcitx5-remote -t ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 2 ;;
esac
