# Do not replace the selection until the capture has completed successfully.
set -euo pipefail
args=()
case "${1:-}" in
  area)
    geometry="$(slurp)" || exit 0
    [[ -n "$geometry" ]] || exit 0
    args=(-g "$geometry")
    ;;
  full) ;;
  *) exit 64 ;;
esac
umask 077
stage="$(mktemp "${XDG_RUNTIME_DIR:?}/jay-screenshot.XXXXXX")"
trap 'rm -f -- "$stage"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
grim "${args[@]}" - > "$stage"
[[ -s "$stage" ]]
wl-copy --type image/png < "$stage"
