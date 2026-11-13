#!/usr/bin/env bash
# Foreground diagnostic: no sudo, no NixOS/runtime state changes. Maximum runtime bounded.
set -euo pipefail
umask 077
samples=${SAMPLES:-12}
interval=${INTERVAL_SECONDS:-1}
case "$samples" in *[!0-9]*|'') echo 'SAMPLES must be integer' >&2;exit 2;; esac
((samples>=2 && samples<=60)) || { echo 'SAMPLES must be 2..60' >&2;exit 2; }
case "$interval" in 1|2) ;; *) echo 'INTERVAL_SECONDS must be 1 or 2' >&2;exit 2;; esac
out="${1:-${PWD}/neko5-observation-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out/samples"
run() { local label=$1;shift; timeout -k 1s 6s "$@" > "$out/$label" 2>&1 || echo "[$label failed or timed out]" >> "$out/$label"; }
run hypr-version.txt hyprctl version
run pipewire-settings.txt pw-metadata -n settings 0
run audio-cards.txt cat /proc/asound/cards
run alsa-hw.txt bash -c 'for p in /proc/asound/card*/pcm*p/sub*/hw_params; do test -r "$p" || continue; printf "== %s\n" "$p"; cat "$p"; done'
run usb-intervals.txt bash -c 'for d in /sys/bus/usb/devices/1-2:1.*/ep_* /sys/bus/usb/devices/1-4.2:1.*/ep_*; do test -f "$d/bInterval" || continue; echo "== $d"; for f in bInterval interval bmAttributes direction; do test -r "$d/$f" && { printf "%s=" "$f";cat "$d/$f"; }; done; done'
printf '\nNow select the osu! window; sampling starts in 8 seconds.\n' >&2
for n in 8 6 4 2;do echo "${n}s..." >&2;sleep 2;done
printf 'Sampling now: %s samples at %ss (switch back only after DONE).\n' "$samples" "$interval" >&2
pw_pid=
if command -v pw-top >/dev/null;then
  # Start *after focus*; previous pre-focus `pw-top` showed inactive C/QUANT=0.
  ( timeout -k 1s 8s pw-top -b -n 4 > "$out/pw-top-active-batch.txt" 2>&1 || echo '[batch pw-top unavailable or timeout]' >> "$out/pw-top-active-batch.txt" ) &
  pw_pid=$!
fi
for ((i=0;i<samples;i++));do
  id=$(printf '%02d' "$i")
  date --iso-8601=ns > "$out/samples/${id}-time.txt"
  timeout -k 1s 3s hyprctl -j monitors > "$out/samples/${id}-monitors.json" 2>&1 || :
  timeout -k 1s 3s hyprctl -j activewindow > "$out/samples/${id}-activewindow.json" 2>&1 || :
  (for p in /sys/class/thermal/thermal_zone*/{type,temp}; do test -r "$p" && printf '%s=%s\n' "$p" "$(cat "$p")"; done; true) > "$out/samples/${id}-thermal.txt"
  (for p in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do test -r "$p" && printf '%s=%s\n' "$p" "$(cat "$p")"; done; true) > "$out/samples/${id}-freq.txt"
  (for p in /sys/devices/system/cpu/cpu[0-9]*/thermal_throttle/*; do test -r "$p" && printf '%s=%s\n' "$p" "$(cat "$p")"; done; true) > "$out/samples/${id}-throttle.txt"
  (for p in /sys/class/powercap/intel-rapl*/energy_uj; do test -r "$p" && printf '%s=%s\n' "$p" "$(cat "$p")"; done; true) > "$out/samples/${id}-rapl.txt"
  echo "Sample $((i+1))/$samples" >&2
  sleep "$interval"
done
[[ -z "$pw_pid" ]] || wait "$pw_pid" || true
printf 'DONE: %s\n' "$out" >&2
printf '%s\n' 'Text dumps may include user paths and hardware serials; inspect before sharing.' >&2
