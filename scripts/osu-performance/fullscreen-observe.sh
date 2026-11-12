#!/usr/bin/env bash
# Read-only Hyprland/osu fullscreen observation, one invocation.
# Captures no screenshots, command lines, secrets, or raw client inventory.
set -u
umask 077
need=(hyprctl jq timeout tar date sleep seq journalctl)
for c in "${need[@]}"; do command -v "$c" >/dev/null || { printf 'Missing command: %s\n' "$c" >&2; exit 2; }; done
stamp=$(date +%Y%m%d-%H%M%S)
out="${PWD}/neko5-fullscreen-${stamp}"
mkdir -m 700 -- "$out" || exit 1
printf 'Output directory: %s\n' "$out"
{
  date -Is
  timeout 2s hyprctl version || :
  timeout 2s hyprctl configerrors || :
  timeout 2s hyprctl getoption render.direct_scanout || :
  timeout 2s hyprctl getoption general.allow_tearing || :
} > "$out/versions.txt" 2>&1
printf 'Switch to osu! and press Win+F once during the next 22 seconds. Starting in 7 seconds.\n'
sleep 7
for i in $(seq 1 15); do
  label=$(printf '%02d' "$i")
  {
    printf '{"iteration": %s, "timestamp": "%s", "clients": ' "$i" "$(date -Is)"
    clients=$(timeout 2s hyprctl -j clients 2>/dev/null | jq -c '[.[] | select(.class == "osu!" or .class == "osu-lazer") | {class, fullscreen, fullscreenClient, at, size, xwayland, tearingHint, workspace}]' 2>/dev/null)
    printf '%s' "${clients:-null}"
    printf ', "monitors": '
    monitors=$(timeout 2s hyprctl -j monitors 2>/dev/null | jq -c '[.[] | select(.name == "eDP-1") | {name, width, height, refreshRate, activeWorkspace, activelyTearing, tearingBlockedBy, directScanoutTo, directScanoutBlockedBy}]' 2>/dev/null)
    printf '%s' "${monitors:-null}"
    printf '}\n'
  } > "$out/sample-${label}.json" 2> "$out/sample-${label}.err"
  printf 'sample %02d/15\n' "$i"
  sleep 1
done
{
  journalctl -k -b --no-pager -n 350 2>&1 | grep -Ei 'i915|drm|gpu.*(hang|reset)|xhci|Hyprland|atomic|flip|modeset' | tail -n 100 || :
} > "$out/kernel-graphics.txt"
archive="${out}.tar.gz"
tar -czf "$archive" -C "$(dirname "$out")" "$(basename "$out")"
printf 'DONE: %s\nInspect archive before sharing; logs may contain device information.\n' "$archive"
