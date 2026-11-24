# Operator convenience only. Incus and Nix own state, not this file.
set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

default:
    @just --list

# Discover immutable workload image outputs; does not build or deploy.
images:
    @nix eval --json .#packages.x86_64-linux --apply builtins.attrNames | jq -r '.[] | select(startswith("neko7-") and endswith("-image")) | sub("^neko7-"; "") | sub("-image$"; "")'

# Native inventory across operator and lab projects.
instances:
    sudo incus list local: --all-projects

# Build, import and start one new durable VM. No host switch. Size is explicit.
new workload name disk cpu="2" memory="2GiB":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ $(hostname -s) == neko7 ]] || { echo "Run on neko7" >&2; exit 1; }
    workload=$1 name=$2 disk=$3 cpu=$4 memory=$5
    [[ $workload =~ ^[a-z][a-z0-9-]*$ && $name =~ ^[a-z][a-z0-9-]{0,62}$ ]] || exit 2
    [[ $disk =~ ^[1-9][0-9]*GiB$ && $cpu =~ ^[1-9][0-9]*$ && $memory =~ ^[1-9][0-9]*GiB$ ]] || exit 2
    out=$(nix build --no-link --print-out-paths ".#neko7-$workload-image")
    test -s "$out/metadata.tar.xz" && test -s "$out/nixos.qcow2"
    base=${out##*/}
    alias="nix-${base%%-*}"
    # Explicit local remote and operator project. Never overwrite an image alias.
    if ! sudo incus image info "local:$alias" --project default >/dev/null 2>&1; then
      sudo incus image import "$out/metadata.tar.xz" "$out/nixos.qcow2" local: --alias "$alias" --project default
    fi
    sudo incus launch "local:$alias" "local:$name" --project default --vm \
      -c security.secureboot=false -c boot.autostart=true \
      -c security.protection.delete=true -c "limits.cpu=$cpu" -c "limits.memory=$memory" \
      -c "user.nixfiles.workload=$workload" -d "root,size=$disk"
    sudo incus info "local:$name" --project default

# Update one managed VM from its declared workload (after an approved backup).
# Explicit backup and typed confirmation; do not downgrade schema automatically.
update name backup:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ $(hostname -s) == neko7 && $1 =~ ^[a-z][a-z0-9-]{0,62}$ && $2 == /* ]] || exit 2
    name=$1 backup=$2
    workload=$(sudo incus config get "local:$name" user.nixfiles.workload --project default)
    [[ $workload =~ ^[a-z][a-z0-9-]*$ ]] || { echo "Not a managed Nix workload" >&2; exit 1; }
    candidate=$(nix build --no-link --print-out-paths ".#neko7-$workload-system")
    test -x "$candidate/bin/switch-to-configuration"
    printf 'Offline backup then update %s to %s. Type instance name: ' "$name" "$candidate"
    read -r confirm
    [[ $confirm == "$name" ]] || exit 1
    just backup "$name" "$backup"
    sudo incus start "local:$name" --project default
    # Agent availability is checked without silently swallowing a failure.
    for ((i=0; i<60; i++)); do
      if sudo incus exec "local:$name" --project default -- true; then break; fi
      sleep 2
    done
    sudo incus exec "local:$name" --project default -- true
    nix-store --export $(nix-store -qR "$candidate") | sudo incus exec "local:$name" --project default -- nix-store --import
    sudo incus exec "local:$name" --project default -- nix-env -p /nix/var/nix/profiles/system --set "$candidate"
    sudo incus exec "local:$name" --project default -- "$candidate/bin/switch-to-configuration" switch
    echo "Verify service health. Backup: $backup"

# Stop one instance and export it to a new absolute path; leave it stopped.
backup name path:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ $(hostname -s) == neko7 && $1 =~ ^[a-z][a-z0-9-]{0,62}$ && $2 == /* ]] || exit 2
    name=$1 path=$2
    sudo test ! -e "$path" && sudo test ! -L "$path" || exit 1
    status=$(sudo incus list local: --project default --format json | jq -er --arg name "$name" '.[] | select(.name == $name) | .status')
    case "$status" in
      Running) sudo incus stop "local:$name" --project default ;;
      Stopped) ;;
      *) echo "Unexpected status: $status" >&2; exit 1 ;;
    esac
    sudo incus export "local:$name" "$path" --project default
    sudo test -s "$path"
    sudo sha256sum "$path"

# Permanent removal: explicit existing verified backup, stopped protected VM.
# Never deletes separate volumes, images, snapshots outside this instance or files.
delete name verified_backup:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ $(hostname -s) == neko7 && $1 =~ ^[a-z][a-z0-9-]{0,62}$ && $2 == /* ]] || exit 2
    name=$1 backup=$2
    sudo test -f "$backup" && sudo test -s "$backup" && sudo test ! -L "$backup"
    sudo sha256sum "$backup"
    workload=$(sudo incus config get "local:$name" user.nixfiles.workload --project default)
    [[ $workload =~ ^[a-z][a-z0-9-]*$ ]] || { echo "Not a managed Nix workload" >&2; exit 1; }
    status=$(sudo incus list local: --project default --format json | jq -er --arg name "$name" '.[] | select(.name == $name) | .status')
    [[ $status == Stopped ]] || { echo "Stop and back up the instance first" >&2; exit 1; }
    [[ $(sudo incus config get "local:$name" security.protection.delete --project default) == true ]] || exit 1
    printf 'Only continue after an isolated restore of this backup. Permanently delete %s? Type its name: ' "$name"
    read -r confirm
    [[ $confirm == "$name" ]] || exit 1
    sudo incus config set "local:$name" security.protection.delete=false --project default
    if ! sudo incus delete "local:$name" --project default; then
      sudo incus config set "local:$name" security.protection.delete=true --project default
      exit 1
    fi

# Ephemeral agent instances use the enrolled restricted remote directly.
lab name image="images:debian/13":
    incus launch "$2" "lab:$1" --ephemeral

lab-vm name image="images:debian/13":
    incus launch "$2" "lab:$1" --vm --ephemeral

# Stopping an ephemeral instance deletes it; export evidence first.
lab-stop name:
    incus stop "lab:$1"
