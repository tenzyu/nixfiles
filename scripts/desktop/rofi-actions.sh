# Static, allowlisted actions; applications and commands use native Rofi modes.
case "${1:-}" in
  custom)
    terminal="${2:-alacritty}"
    case "$terminal" in foot|alacritty) ;; *) exit 2 ;; esac
    selection="$(printf '%s\n' 'Nixfiles shell' 'Nixfiles GitUI' 'System monitor' 'Disk usage' |
      rofi -dmenu -replace -i -no-custom -format s -p Commands)" || exit 0
    case "$selection" in
      'Nixfiles shell') exec "$terminal" --working-directory "$HOME/.nixfiles" ;;
      'Nixfiles GitUI') exec "$terminal" --working-directory "$HOME/.nixfiles" -e gitui ;;
      'System monitor') exec "$terminal" -e btop ;;
      'Disk usage') exec "$terminal" -e dua i ;;
      *) exit 0 ;;
    esac
    ;;
  desktop)
    selection="$(printf '%s\n' 'Jay control center' 'Open Jay config directory' 'Toggle input method' |
      rofi -dmenu -replace -i -no-custom -format s -p Desktop)" || exit 0
    case "$selection" in
      'Jay control center') exec jay control-center ;;
      'Open Jay config directory') exec jay config open-dir ;;
      'Toggle input method') exec fcitx5-remote -t ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 2 ;;
esac
