{...}: {
  flake.modules.nixos.nix-store-clean = {pkgs, ...}: let
    nixStoreCleanCurrentSystem = pkgs.writeShellApplication {
      name = "nix-store-clean-current-system";
      runtimeInputs = with pkgs; [
        coreutils
        gawk
        gnugrep
        gnused
        nix
      ];
      text = ''
        set -euo pipefail

        usage() {
          cat <<'USAGE'
        Usage:
          nix-store-clean-current-system [--dry-run|--list|--delete --yes] [options]

        Delete every valid /nix/store path that is outside the selected system closure.
        The default root is /run/current-system, and normal GC liveness roots are ignored
        during deletion so stale profiles, generations, and user roots cannot keep old paths.

        Modes:
          --dry-run            Print candidate count and size without deleting anything (default)
          --list               Print candidate store paths
          --delete             Delete candidate paths with nix store delete --ignore-liveness
          --yes                Required with --delete

        Options:
          --root PATH          Keep PATH's closure instead of /run/current-system
          --keep PATH          Also keep PATH's closure. Can be passed more than once
          --keep-booted        Also keep /run/booted-system's closure
          --allow-booted-diff  Continue even when /run/booted-system differs from --root
          -h, --help           Show this help
        USAGE
        }

        mode="dry-run"
        root="/run/current-system"
        yes=0
        keep_booted=0
        allow_booted_diff=0
        keep_paths=()

        while [ "$#" -gt 0 ]; do
          case "$1" in
            --dry-run)
              mode="dry-run"
              ;;
            --list)
              mode="list"
              ;;
            --delete)
              mode="delete"
              ;;
            --yes)
              yes=1
              ;;
            --root)
              if [ "$#" -lt 2 ]; then
                echo "error: --root requires a path" >&2
                exit 2
              fi
              root="$2"
              shift
              ;;
            --keep)
              if [ "$#" -lt 2 ]; then
                echo "error: --keep requires a path" >&2
                exit 2
              fi
              keep_paths+=("$2")
              shift
              ;;
            --keep-booted)
              keep_booted=1
              ;;
            --allow-booted-diff)
              allow_booted_diff=1
              ;;
            -h|--help)
              usage
              exit 0
              ;;
            *)
              echo "error: unknown argument: $1" >&2
              usage >&2
              exit 2
              ;;
          esac
          shift
        done

        if [ "$mode" = "delete" ] && [ "$yes" -ne 1 ]; then
          echo "error: --delete requires --yes" >&2
          exit 2
        fi

        if [ "$mode" = "delete" ] && [ "$(id -u)" -ne 0 ]; then
          echo "error: deletion must run as root" >&2
          exit 1
        fi

        if [ ! -e "$root" ]; then
          echo "error: root path does not exist: $root" >&2
          exit 1
        fi

        root_target="$(readlink -f "$root")"
        if ! printf '%s\n' "$root_target" | grep -q '^/nix/store/'; then
          echo "error: root path does not resolve into /nix/store: $root" >&2
          exit 1
        fi

        if [ -e /run/booted-system ]; then
          booted_target="$(readlink -f /run/booted-system)"
          if [ "$booted_target" != "$root_target" ] && [ "$keep_booted" -ne 1 ] && [ "$allow_booted_diff" -ne 1 ]; then
            cat >&2 <<EOF
        error: /run/booted-system differs from $root
          root:   $root_target
          booted: $booted_target

        Reboot into the current system, pass --keep-booted to preserve the booted closure,
        or pass --allow-booted-diff to clean strictly against $root anyway.
        EOF
            exit 1
          fi
        fi

        tmpdir="$(mktemp -d)"
        trap 'rm -rf "$tmpdir"' EXIT

        keep_unsorted="$tmpdir/keep.unsorted"
        keep_sorted="$tmpdir/keep.sorted"
        all_sorted="$tmpdir/all.sorted"
        candidates="$tmpdir/candidates"

        nix-store --query --requisites "$root" > "$keep_unsorted"

        if [ "$keep_booted" -eq 1 ] && [ -e /run/booted-system ]; then
          nix-store --query --requisites /run/booted-system >> "$keep_unsorted"
        fi

        for keep_path in "''${keep_paths[@]}"; do
          if [ ! -e "$keep_path" ]; then
            echo "error: keep path does not exist: $keep_path" >&2
            exit 1
          fi
          nix-store --query --requisites "$keep_path" >> "$keep_unsorted"
        done

        sort -u "$keep_unsorted" > "$keep_sorted"
        nix path-info --all | sort -u > "$all_sorted"
        comm -23 "$all_sorted" "$keep_sorted" > "$candidates"

        count="$(wc -l < "$candidates" | tr -d ' ')"
        if [ "$count" -eq 0 ]; then
          bytes=0
        else
          bytes="$(nix path-info --stdin --size < "$candidates" | sed -n 's/.*[[:space:]]\([0-9][0-9]*\)$/\1/p' | awk '{ sum += $1 } END { print sum + 0 }')"
        fi
        human_bytes="$(numfmt --to=iec-i --suffix=B "$bytes")"

        case "$mode" in
          dry-run)
            printf 'root: %s -> %s\n' "$root" "$root_target"
            printf 'candidates: %s paths, %s\n' "$count" "$human_bytes"
            printf 'delete command: sudo nix-store-clean-current-system --delete --yes\n'
            ;;
          list)
            cat "$candidates"
            ;;
          delete)
            printf 'root: %s -> %s\n' "$root" "$root_target"
            printf 'deleting: %s paths, %s\n' "$count" "$human_bytes"
            if [ "$count" -eq 0 ]; then
              exit 0
            fi
            nix store delete --ignore-liveness --stdin < "$candidates"
            ;;
        esac
      '';
    };
  in {
    environment.systemPackages = [
      nixStoreCleanCurrentSystem
    ];
  };
}
