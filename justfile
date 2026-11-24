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

# A read-only view of native managers, no persisted inventory.
status:
    @sudo incus list local: --all-projects
    @systemctl list-units 'container@*.service' --all --no-pager
    @systemctl --user list-units --type=service --state=running,failed --no-pager
    @systemctl --failed --no-pager
    @free -h
    @df -h / /nix/store

# Build a durable VM image, then call the exact same artifact operation used in CI.
new workload name disk cpu="2" memory="2GiB":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ $(hostname -s) == neko7 && $1 =~ ^[a-z][a-z0-9-]*$ ]] || exit 2
    build_root=$(mktemp -d)
    trap 'rm -rf -- "$build_root"' EXIT
    nix build --out-link "$build_root/result" ".#neko7-$1-image"
    just _new-image "$1" "$2" "$3" "$4" "$5" "$(readlink -e "$build_root/result")"

# Build independently, then apply under the same native lock as backup.
update name backup:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ $(hostname -s) == neko7 && $1 =~ ^[a-z][a-z0-9-]{0,62}$ && $2 == /* ]] || exit 2
    workload=$(sudo incus config get "local:$1" user.nixfiles.workload --project default)
    uuid=$(sudo incus config get "local:$1" volatile.uuid --project default)
    [[ $workload =~ ^[a-z][a-z0-9-]*$ && -n $uuid ]] || exit 2
    build_root=$(mktemp -d)
    trap 'rm -rf -- "$build_root"' EXIT
    nix build --out-link "$build_root/result" ".#neko7-$workload-system"
    printf 'Offline backup and update %s. Type instance name: ' "$1"
    read -r confirm
    [[ $confirm == "$1" ]] || exit 1
    just _update-system "$1" "$2" "$workload" "$uuid" "$(readlink -e "$build_root/result")"

# Stop and export to a new private bundle directory. Leaves instance stopped.
backup name directory:
    bash tools/instance-ops.sh backup "$1" "$2"

_new-image workload name disk cpu memory image:
    bash tools/instance-ops.sh new "$@"

_update-system name directory workload uuid system:
    bash tools/instance-ops.sh update "$@"

# Ephemeral agent instances use the enrolled restricted remote directly.
lab name image="images:debian/13":
    incus launch "$2" "lab:$1" --ephemeral

lab-vm name image="images:debian/13":
    incus launch "$2" "lab:$1" --vm --ephemeral

# Stopping an ephemeral instance deletes it; export evidence first.
lab-stop name:
    incus stop "lab:$1"
