# Invoked via Herdr's private PATH prefix, not installed as a global wl-copy.
# A nonzero status selects Herdr's built-in OSC 52 fallback. No data is read.
if [[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" &&
      "$#" == 2 && "$1" == --type && "$2" == 'text/plain;charset=utf-8' ]]; then
  caller="$(@READLINK@ -f "/proc/$PPID/exe" 2>/dev/null)" || caller=
  if [[ "$caller" == "$(@READLINK@ -f @HERDR@)" ]]; then
    exit 1
  fi
fi
exec @WL_COPY@ "$@"
