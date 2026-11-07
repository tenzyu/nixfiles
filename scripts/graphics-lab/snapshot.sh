#!/usr/bin/env bash
# Non-privileged, read-only NixOS/i915/VA-API baseline inventory.
set -uo pipefail
OUT="${1:-$PWD/kernel-stream-snapshot-$(date +%Y%m%dT%H%M%S)}"
mkdir -p -- "$OUT"
chmod 700 "$OUT"
OUT="$(realpath "$OUT")"
log() { printf '[snapshot] %s\n' "$*" >&2; }
run() {
  local name="$1"; shift
  if command -v "$1" >/dev/null 2>&1; then
    timeout 15 "$@" > "$OUT/$name.txt" 2>&1 || printf '\n[command exited nonzero/timeout]\n' >> "$OUT/$name.txt"
  else
    printf 'NOT_AVAILABLE: %s\n' "$1" > "$OUT/$name.txt"
  fi
}
{
  printf 'kernel='; uname -r
  printf 'architecture='; uname -m
  printf 'boot_parameters='; cat /proc/cmdline
  printf 'session='; printf '%s\n' "${XDG_SESSION_TYPE:-unknown}"
  printf 'libva_driver='; printf '%s\n' "${LIBVA_DRIVER_NAME:-unset}"
  printf 'i915_loaded='; test -d /sys/module/i915 && echo yes || echo no
} > "$OUT/kernel.txt"
run lscpu lscpu -e=CPU,CORE,SOCKET,ONLINE,MAXMHZ,MINMHZ
run pci lspci -nnk
run lsusb lsusb -t
run cpu-thermal sensors
run vaapi vainfo --display drm --device /dev/dri/renderD128
run gsr-info gpu-screen-recorder --info
run gsr-targets gpu-screen-recorder --list-capture-options
run ffmpeg-encoders ffmpeg -hide_banner -encoders
run ffmpeg-h264-vaapi ffmpeg -hide_banner -h encoder=h264_vaapi
run gpu-tools intel_gpu_top -h
run network-link ip -brief link
run hyprland-version hyprctl version
run journal-kernel journalctl -k -b --no-pager -n 300
{
 for policy in /sys/devices/system/cpu/cpufreq/policy*; do
   test -d "$policy" || continue
   printf '\n[%s]\n' "${policy##*/}"
   for key in scaling_driver scaling_governor scaling_cur_freq cpuinfo_max_freq energy_performance_preference energy_performance_available_preferences; do
     test -r "$policy/$key" && printf '%s=%s\n' "$key" "$(cat "$policy/$key")"
   done
 done
} > "$OUT/cpufreq.txt"
{
 for key in /sys/module/i915/parameters/{enable_guc,enable_fbc,enable_psr,enable_dc,fastboot,enable_hangcheck}; do
   if test -r "$key"; then printf '%s=%s\n' "$key" "$(cat "$key")"; else printf '%s=UNAVAILABLE\n' "$key"; fi
 done
} > "$OUT/i915-parameters.txt"
{
 for path in /sys/class/drm/card*/device/driver/module /sys/class/drm/renderD*/device/driver/module; do
   test -e "$path" && printf '%s -> %s\n' "$path" "$(readlink -f "$path")"
 done
} > "$OUT/gpu-driver.txt"
if command -v hyprctl >/dev/null && command -v python3 >/dev/null; then
  hyprctl monitors -j 2> "$OUT/monitors-error.txt" | python3 -c 'import sys,json; d=json.load(sys.stdin); fields=("name","width","height","scale","directScanoutTo","directScanoutBlockedBy","solitaryBlockedBy","activelyTearing"); print(json.dumps([{k:v for k,v in x.items() if k in fields} for x in d],ensure_ascii=False,indent=2))' > "$OUT/monitors.json" 2>> "$OUT/monitors-error.txt" || printf 'unavailable\n' > "$OUT/monitors.json"
fi
printf 'Do not upload diagnostics without inspecting for private data.\n' > "$OUT/PRIVACY.txt"
log "Wrote $OUT (read-only; no kernel or NixOS setting was changed)"
