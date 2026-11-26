#!/usr/bin/env bash
# Read-only, current-identity probes. No authority escalation or execution adapter.
set -eu
probe() {
  if command -v "$1" >/dev/null 2>&1 && timeout 5s "$@" >/dev/null 2>&1; then
    printf true
  else
    printf false
  fi
}
lab_authenticated=false
drivers=""
if command -v incus >/dev/null 2>&1; then
  if server=$(timeout 5s incus query 'lab:/1.0?project=lab' 2>/dev/null) &&
    jq -e '.auth == "trusted" and .environment.project == "lab" and .environment.server_clustered == false' >/dev/null 2>&1 <<<"$server" && [ -n "$server" ] && timeout 5s incus list lab: --format=json >/dev/null 2>&1; then
    lab_authenticated=true
    drivers=$(jq -r '.environment.driver // ""' <<<"$server")
  fi
fi
rootless=false
if command -v docker >/dev/null 2>&1; then
  if opts=$(timeout 5s docker info --format '{{json .SecurityOptions}}' 2>/dev/null) &&
    jq -e 'type == "array" and any(.[]; type == "string" and (split(",") | index("name=rootless") != null))' >/dev/null 2>&1 <<<"$opts"; then
    rootless=true
  fi
fi
kvm_present=false
if [ -c /dev/kvm ]; then kvm_present=true; fi
jq -n \
  --argjson user_systemd "$(probe systemctl --user show-environment)" \
  --argjson nix_store "$(probe nix store ping)" \
  --argjson rootless_docker "$rootless" \
  --argjson lab_authenticated "$lab_authenticated" \
  --arg drivers "$drivers" \
  --argjson kvm_present "$kvm_present" \
  '{user_systemd:$user_systemd,nix_store:$nix_store,rootless_docker:$rootless_docker,incus:{lab_authenticated:$lab_authenticated,advertised_drivers:($drivers|split(" | ")|map(select(length>0)))},host_kvm_device_present:$kvm_present}'
