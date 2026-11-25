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

# Ephemeral agent instances use the enrolled restricted remote directly.
lab name image="images:debian/13":
    incus launch "$2" "lab:$1" --ephemeral

# Stopping an ephemeral instance deletes it; export evidence first.
lab-stop name:
    incus stop "lab:$1"
