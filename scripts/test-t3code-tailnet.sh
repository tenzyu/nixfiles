#!/usr/bin/env bash
# Exercise the evaluated restore script with a recording substitute for tailscale.
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
cp "$1" "$tmp/restore"
cat > "$tmp/tailscale" <<'STUB'
#!/usr/bin/env bash
set -eu
case "$*" in
  'status --json') echo '{"Self":{"DNSName":"fixture.invalid."}}' ;;
  'serve status --json') echo "$STATE" ;;
  *) printf '%s\n' "$*" >> "$CALLS" ;;
esac
STUB
chmod +x "$tmp/tailscale"
export PATH="$tmp:$PATH" CALLS="$tmp/calls"
check() {
  local name=$1 expected_status=$2 expected_call=$3 status=0
  : > "$CALLS"
  STATE=$4 bash "$tmp/restore" > "$tmp/log" 2>&1 || status=$?
  if [[ $status != "$expected_status" || $(cat "$CALLS") != "$expected_call" ]]; then
    cat "$tmp/log" "$CALLS" >&2
    echo "$name: unexpected exit ($status) or write" >&2
    return 1
  fi
  echo "$name: PASS"
}
other='{"TCP":{"443":{"HTTPS":true}}}'
present=$(jq '.TCP["8445"] = {HTTPS:true} | .Web["fixture.invalid:8445"].Handlers["/"].Proxy = "http://127.0.0.1:3773"' <<< "$other")
check present 0 '' "$present"
check absent 0 'serve --bg --https=8445 http://127.0.0.1:3773' "$other"
check occupied 1 '' "$(jq '.Web["fixture.invalid:8445"].Handlers["/"].Proxy = "http://127.0.0.1:4096"' <<< "$present")"
check funnel 1 '' "$(jq '.AllowFunnel["fixture.invalid:8445"] = true' <<< "$present")"
check foreground 1 '' "$(jq -n --argjson route "$present" '{Foreground:{session:$route}}')"
