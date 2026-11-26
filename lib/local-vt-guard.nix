session: ''
  set -eu
  if [ "$(id -u)" = 0 ] || [ ! -t 0 ] || [ -n "''${SSH_CONNECTION:-}" ] || [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
    echo "Start ${session} as a normal user from a local text VT." >&2
    exit 1
  fi
''
