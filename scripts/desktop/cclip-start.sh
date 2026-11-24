# Start once on Jay's privileged Wayland socket. No extra resident wrapper.
umask 077
dir="${XDG_DATA_HOME:-$HOME/.local/share}/cclip"
mkdir -p -m 700 -- "$dir"
[[ ! -L "$dir" && -O "$dir" && ! -L "$dir/db.sqlite3" ]] || exit 1
chmod 700 -- "$dir"
# cclipd has no singleton guard; flock --no-fork retains the lock across exec.
exec flock --nonblock --no-fork "$dir/capture.lock" cclipd -c 512 -P 160 \
  -t image/png -t 'image/*' -t 'text/plain;charset=utf-8' -t text/plain -t 'text/*'
