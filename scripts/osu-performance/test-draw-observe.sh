#!/usr/bin/env bash
# Offline fixture tests; no Hyprland session, graphics device or game needed.
set -Eeuo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  '-j monitors')
    if [[ ${TEST_DSO:-yes} == yes ]]; then
      echo '[{"name":"eDP-1","width":1366,"height":768,"refreshRate":60.003,"directScanoutTo":"0x12345","directScanoutBlockedBy":[]}]'
    else
      echo '[{"name":"eDP-1","width":1366,"height":768,"refreshRate":60.003,"directScanoutTo":"0","directScanoutBlockedBy":["TRANSFORM"]}]'
    fi
    ;;
  '-j clients')
    printf '[{"class":"osu!","fullscreen":2,"fullscreenClient":%s,"xwayland":false}]\n' "${TEST_CLIENT_FS:-0}"
    ;;
  '-j activewindow') printf '{"class":"%s"}\n' "${TEST_ACTIVE_CLASS:-osu!}";;
  '-j getoption '*) echo '{"int":1}';;
  *) exit 1;;
esac
MOCK
chmod +x "$tmp/bin/hyprctl"
export PATH="$tmp/bin:$PATH" SAMPLES=3 INTERVAL_SECONDS=0
TEST_DSO=yes "$script_dir/draw-observe.sh" "$tmp/pass" >/dev/null
[[ $(jq -r .known_good_geometry_dso_samples "$tmp/pass/summary.json") == 3 ]]
TEST_DSO=no "$script_dir/draw-observe.sh" "$tmp/blocked" >/dev/null
[[ $(jq -r .known_good_geometry_dso_samples "$tmp/blocked/summary.json") == 0 ]]
[[ $(jq -r '.blockers[0].reason' "$tmp/blocked/summary.json") == '["TRANSFORM"]' ]]
TEST_DSO=yes TEST_CLIENT_FS=2 "$script_dir/draw-observe.sh" "$tmp/2-2" >/dev/null
[[ $(jq -r .known_good_geometry_samples "$tmp/2-2/summary.json") == 0 ]]
TEST_ACTIVE_CLASS=Firefox "$script_dir/draw-observe.sh" "$tmp/other-focus" >/dev/null
[[ $(jq -r .foreground_samples "$tmp/other-focus/summary.json") == 0 ]]
echo 'PASS: 4 draw-observe fixture scenarios'
