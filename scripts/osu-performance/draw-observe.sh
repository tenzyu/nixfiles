#!/usr/bin/env bash
# Read-only observation of DSO eligibility, thermal counters and P-state policy.
# This is NOT a frame-time, KMS flip timestamp, input-to-photon or panel test.
set -Eeuo pipefail
umask 077

samples="${SAMPLES:-30}"
interval="${INTERVAL_SECONDS:-1}"
[[ "$samples" =~ ^[0-9]+$ ]] && (( samples >= 2 && samples <= 120 )) || {
  echo 'SAMPLES must be 2..120' >&2; exit 64;
}
case "$interval" in 0|0.2|0.5|1|2) :;; *) echo 'INTERVAL_SECONDS must be 0, 0.2, 0.5, 1 or 2' >&2; exit 64;; esac
for cmd in jq hyprctl timeout date; do
  command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 127; }
done
out="${1:-${PWD}/neko5-draw-$(date +%Y%m%d-%H%M%S)}"
[[ ! -e "$out" ]] || { echo "refusing to overwrite: $out" >&2; exit 73; }
mkdir -m 700 -p -- "$out"

printf 'timestamp=%s\n' "$(date -Is)" > "$out/metadata.txt"
printf 'kernel=%s\n' "$(uname -r)" >> "$out/metadata.txt"
printf 'samples=%s\ninterval_s=%s\n' "$samples" "$interval" >> "$out/metadata.txt"
for key in render:direct_scanout render:new_render_scheduling general:allow_tearing misc:vrr; do
  { printf '%s\t' "$key"; timeout 3s hyprctl -j getoption "$key" || :; } >> "$out/options.txt" 2>/dev/null
done

read_file() {
  local p=$1
  if [[ -r "$p" ]]; then cat "$p" 2>/dev/null || printf 'null'; else printf 'null'; fi
}
# Prefer the actual Intel package zone. Never invent a temperature if missing.
package_temp() {
  local d typ
  for d in /sys/class/thermal/thermal_zone*; do
    [[ -r "$d/type" && -r "$d/temp" ]] || continue
    typ=$(cat "$d/type")
    if [[ "$typ" == x86_pkg_temp ]]; then cat "$d/temp"; return; fi
  done
  printf 'null'
}
num_or_null() {
  if [[ "$1" =~ ^[0-9]+$ ]]; then printf '%s' "$1"; else printf 'null'; fi
}

printf 'Sampling Hyprland every %s s, %s samples. Keep osu! foreground.\n' "$interval" "$samples" >&2
: > "$out/samples.jsonl"
for ((i=0; i<samples; i++)); do
  # A failed IPC query becomes {}, never evidence of failed direct scanout.
  mon=$(timeout 3s hyprctl -j monitors 2>/dev/null | jq -c '[.[] | select(.name=="eDP-1") | {name,width,height,refreshRate,vrr,activelyTearing,tearingBlockedBy,directScanoutTo,directScanoutBlockedBy}] | first // {}' 2>/dev/null) || mon='{}'
  win=$(timeout 3s hyprctl -j clients 2>/dev/null | jq -c '[.[] | select(.class=="osu!" or .class=="osu-lazer") | {class,fullscreen,fullscreenClient,xwayland,size,at,workspace,tearingHint}] | first // {}' 2>/dev/null) || win='{}'
  active=$(timeout 3s hyprctl -j activewindow 2>/dev/null | jq -c '{class,fullscreen,fullscreenClient}' 2>/dev/null) || active='{}'
  [[ -n "$mon" ]] || mon='{}'
  [[ -n "$win" ]] || win='{}'
  [[ -n "$active" ]] || active='{}'
  temp=$(num_or_null "$(package_temp)")
  throttle=$(num_or_null "$(read_file /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count)")
  freq=$(num_or_null "$(read_file /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)")
  governor=$(read_file /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)
  epp=$(read_file /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference)
  jq -nc --arg timestamp "$(date -Is)" --argjson monitor "$mon" --argjson window "$win" \
    --argjson active "$active" --argjson temp_millic "$temp" --argjson throttle "$throttle" \
    --argjson freq_khz "$freq" --arg governor "$governor" --arg epp "$epp" \
    '{timestamp:$timestamp,monitor:$monitor,window:$window,active:$active,
      package_temp_mC:$temp_millic,package_throttle_count:$throttle,
      cpu0_freq_kHz:$freq_khz,cpu_governor:$governor,cpu_epp:$epp}' >> "$out/samples.jsonl"
  if (( i + 1 < samples )); then sleep "$interval"; fi
done
jq -s '
  def foreground: (.active.class == "osu!" or .active.class == "osu-lazer");
  def eligible: (foreground and .window.fullscreen == 2 and .window.fullscreenClient == 0 and .monitor.name == "eDP-1");
  def dso: (.monitor.directScanoutTo != null and (.monitor.directScanoutTo|tostring) != "0" and (.monitor.directScanoutTo|tostring) != "");
  {sample_count:length,
   foreground_samples:([.[] | select(foreground)]|length),
   known_good_geometry_samples:([.[] | select(eligible)]|length),
   known_good_geometry_dso_samples:([.[] | select(eligible and dso)]|length),
   sampled_direct_scanout_positive:([.[] | select(dso)]|length),
   blockers:([.[] | select(eligible and (dso|not)) | .monitor.directScanoutBlockedBy] | map(tostring) | group_by(.) | map({reason:.[0],samples:length})),
   cpu_temp_max_C:([.[].package_temp_mC | select(type=="number")]|if length>0 then max/1000 else null end),
   cpu_throttle_counter_delta:([.[].package_throttle_count | select(type=="number")] | if length>=2 then last-first else null end),
   caveat:"Hyprland sampled state only; not per-frame flip rate, scanout duration, or input-to-photon latency. Missing/foreground transitions affect counts."}' \
  "$out/samples.jsonl" > "$out/summary.json"
cat "$out/summary.json"
printf 'Raw evidence: %s\nPrivate logs; inspect before sharing.\n' "$out" >&2
