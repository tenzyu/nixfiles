#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  game list | status [ark|rust|minecraft|all]
  game start|stop|restart|logs|ip|console|backup|update GAME
  game send minecraft 'COMMAND'
  game exec GAME COMMAND [ARGS...]

The 'game' command runs on the neko7 host.
HELP
}

if (($# < 1)); then usage; exit 2; fi
action=$1; shift

declare -A service=(
  [ark]=ark-survival-evolved
  [rust]=rust-dedicated
  [minecraft]=minecraft-server-survival
)
declare -A update_service=(
  [ark]=ark-survival-evolved-update
  [rust]=rust-dedicated-update
)
declare -A data=(
  [ark]=/home/game-ark/ark/server/ShooterGame/Saved
  [rust]=/home/game-rust/rust/server/server
  [minecraft]=/home/game-minecraft/minecraft/survival
)
declare -A backups=(
  [ark]=/home/game-ark/ark/backups
  [rust]=/home/game-rust/rust/backups
  [minecraft]=/home/game-minecraft/minecraft/backups
)

container() { printf 'neko7-%s' "$1"; }
require_game() {
  game=${1:-}
  if [[ ! -v service[$game] ]]; then
    printf 'Unknown game: %s\n' "$game" >&2
    usage >&2
    exit 2
  fi
  unit=${service[$game]}
  node=$(container "$game")
}
up() { sudo systemctl is-active --quiet "container@${node}.service"; }
inside() { sudo nixos-container run "$node" -- "$@"; }
running() { up && inside systemctl is-active --quiet "$unit"; }
ensure_container() { sudo systemctl start "container@${node}.service"; }

status_one() {
  require_game "$1"
  if ! up; then
    printf '%-12s %s\n' "$game" 'container stopped'
  elif running; then
    printf '%-12s %s\n' "$game" 'running'
  else
    printf '%-12s %s\n' "$game" 'container up / server stopped or failed'
  fi
}

case "$action" in
  help|-h|--help) usage ;;
  list|status)
    target=${1:-all}
    if [[ $target == all ]]; then
      for target in ark rust minecraft; do status_one "$target"; done
    else
      require_game "$target"
      status_one "$game"
    fi
    ;;
  *)
    require_game "${1:-}"
    shift || true
    case "$action" in
      start)
        ensure_container
        inside systemctl start "$unit"
        ;;
      stop)
        if up; then inside systemctl stop "$unit"; fi
        ;;
      restart)
        ensure_container
        inside systemctl restart "$unit"
        ;;
      logs)
        if ! up; then echo "Container $node is stopped" >&2; exit 1; fi
        inside journalctl -u "$unit" -n 100 -f
        ;;
      ip)
        if ! up; then echo "Container $node is stopped" >&2; exit 1; fi
        inside tailscale ip -4
        ;;
      console)
        if [[ $game != minecraft ]]; then
          echo 'Interactive console currently supported only for Minecraft; use game exec / logs for other games.' >&2
          exit 2
        fi
        if ! running; then echo 'Minecraft server is not running' >&2; exit 1; fi
        inside tmux -S /run/minecraft/survival.sock attach
        ;;
      send)
        if [[ $game != minecraft || $# != 1 ]]; then
          echo "Usage: game send minecraft 'COMMAND'" >&2; exit 2
        fi
        if ! running; then echo 'Minecraft server is not running' >&2; exit 1; fi
        inside tmux -S /run/minecraft/survival.sock send-keys -l -- "$1"
        inside tmux -S /run/minecraft/survival.sock send-keys Enter
        ;;
      exec)
        if (($# == 0)); then echo 'Usage: game exec GAME COMMAND [ARGS...]' >&2; exit 2; fi
        ensure_container
        inside "$@"
        ;;
      update)
        if [[ ! -v update_service[$game] ]]; then
          echo "No update unit for $game. Rebuild the NixOS configuration to update Minecraft." >&2
          exit 2
        fi
        ensure_container
        was_running=0
        if running; then was_running=1; inside systemctl stop "$unit"; fi
        if inside systemctl start "${update_service[$game]}"; then
          if ((was_running)); then inside systemctl start "$unit"; fi
        else
          echo "Update failed. Server left stopped. See: game exec $game journalctl -u ${update_service[$game]}" >&2
          exit 1
        fi
        ;;
      backup)
        ensure_container
        was_running=0
        if running; then was_running=1; inside systemctl stop "$unit"; fi
        source=${data[$game]}
        destination=${backups[$game]}
        if ! sudo test -d "$source"; then
          echo "Missing backup source: $source" >&2
          if ((was_running)); then inside systemctl start "$unit"; fi
          exit 1
        fi
        if ! sudo test -d "$destination"; then
          echo "Missing backup directory: $destination" >&2
          if ((was_running)); then inside systemctl start "$unit"; fi
          exit 1
        fi
        archive="$destination/${game}-$(date +%Y%m%d-%H%M%S).tar.gz"
        if sudo -u "game-$game" tar -C "$(dirname "$source")" -czf "$archive" "$(basename "$source")"; then
          echo "Created: $archive"
          if ((was_running)); then inside systemctl start "$unit"; fi
        else
          echo "Backup failed; server is stopped. Remove incomplete archive: $archive" >&2
          exit 1
        fi
        ;;
      *) echo "Unknown action: $action" >&2; usage >&2; exit 2 ;;
    esac
    ;;
esac
