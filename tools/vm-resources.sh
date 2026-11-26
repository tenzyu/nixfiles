# Guest-visible capacity, not a reservation or admission budget.
# Native CLI convenience only; no scheduler or persistent state.
vm_resources() {
  local remote=$1 project=$2; shift 2
  local cpu memory disk resources
  # Read the backend itself rather than the calling process's cgroup/CPU view.
  resources=$("$@" query "$remote:/1.0/resources?project=$project") || return
  cpu=$(jq -er '.cpu.total | select(type == "number" and . > 0) | floor | tostring' <<< "$resources") || return
  memory=$(jq -er '.memory.total | select(type == "number" and . >= 1048576) | (. / 1048576 | floor | tostring) + "MiB"' <<< "$resources") || return
  disk=$("$@" query "$remote:/1.0/storage-pools/default/resources?project=$project" |
    jq -er '.space.total | select(type == "number" and . > 0) | floor | tostring') || return
  [[ $cpu =~ ^[1-9][0-9]*$ && $memory =~ ^[1-9][0-9]*MiB$ && $disk =~ ^[1-9][0-9]*$ ]] || return 2
  vm_args=(-c "limits.cpu=$cpu" -c "limits.memory=$memory" -d "root,size=${disk}B")
  printf 'VM guest capacity: %s vCPU, %s RAM, %s B virtual disk (shared host; not reserved)\n' "$cpu" "$memory" "$disk" >&2
}
launch_lab_vm() {
  local name=${1:?instance name required} image=${2:-images:debian/13}
  [[ $# -ge 1 && $# -le 2 && $name =~ ^[a-z][a-z0-9-]{0,62}$ ]] || return 2
  [[ $(hostname -s) == neko7 ]] || { echo "Run on neko7" >&2; return 2; }
  local -a vm_args
  vm_resources lab lab incus || return
  incus launch "$image" "lab:$name" --vm --ephemeral "${vm_args[@]}"
}
