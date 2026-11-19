#!/usr/bin/env python3
"""Select affected Nix checks without treating full flake check as a PR gate."""

import argparse
import os
import subprocess
import sys
from pathlib import PurePosixPath

OPTIONAL_CHECKS = (
    "home-migration",
    "nix-store-clean",
    "safety-python",
    "opencode-direnv",
    "rtk-rewrites",
    "safety-shell",
    "steam-gaming",
    "game-backup-minecraft",
)


# Each module here declares local.homeMigration.paths outside the home/ domain.
MIGRATION_RULE_OWNERS = {
    "modules/50-features/bundles/common.nix",
    "modules/50-features/cli/zsh.nix",
    "modules/50-features/desktop/firefox.nix",
}


def selection(changed_paths: list[str]) -> tuple[list[str], bool]:
    checks: set[str] = set()
    cache_probe = False
    for raw in changed_paths:
        path = PurePosixPath(raw).as_posix()
        if (
            path in ("flake.lock", "flake.nix", "modules/10-foundations/overlays.nix")
            or path.startswith("modules/00-hosts/")
            or (
                path.startswith("modules/_internal/configurations/")
                and not path.startswith("modules/_internal/configurations/tests/")
            )
        ):
            # Shared inputs and host selections can affect any feature check.
            checks.update(OPTIONAL_CHECKS)
            cache_probe = True
        if path.startswith(("modules/50-features/home/", "assets/home-layout/")) or path in MIGRATION_RULE_OWNERS:
            checks.add("home-migration")
        if path == "modules/50-features/nix/nix-store-clean.nix" or path.startswith("assets/nix-store-clean/"):
            checks.add("nix-store-clean")
        if path.startswith("assets/safety/python/") or path == "modules/10-foundations/safety-python-check.nix":
            checks.add("safety-python")
        if path == "modules/50-features/development/opencode-direnv.nix" or path.startswith("assets/opencode/"):
            checks.add("opencode-direnv")
        if path == "modules/50-features/development/rtk.nix" or path.startswith("assets/rtk/"):
            checks.add("rtk-rewrites")
        if path.startswith("assets/safety/shell/") or path in (
            "fixtures/contracts/safety-shell.md",
            "modules/10-foundations/safety-shell-check.nix",
        ):
            checks.add("safety-shell")
        if path == "modules/50-features/gaming/steam.nix" or path.startswith("assets/steam-gaming/"):
            checks.add("steam-gaming")
        if (path.startswith("modules/50-features/media/") or path in (
            "modules/50-features/nix/nix.nix",
            "scripts/ci/audit-splitcast-cache.sh",
        )):
            cache_probe = True
        if path.startswith((
            "assets/safety/shell/",
            "modules/50-features/game-servers/_internal/minecraft-backup/",
        )) or path in (
            "lib/service-layout.nix",
            "modules/10-foundations/game-backup-minecraft-check.nix",
            "modules/50-features/game-servers/_internal/container.nix",
            "modules/50-features/game-servers/_internal/game.sh",
            "modules/50-features/game-servers/commands.nix",
            "modules/50-features/game-servers/minecraft.nix",
        ):
            checks.add("game-backup-minecraft")
    return sorted(checks), cache_probe


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default=os.environ.get("NIX_CHECK_BASE") or "HEAD^", help="PR merge first parent or push event before SHA")
    parser.add_argument("--cache-only", action="store_true")
    args = parser.parse_args()

    try:
        paths = subprocess.check_output(
            ["git", "diff", "--name-only", args.base, "HEAD"], text=True
        ).splitlines()
        checks, cache_probe = selection(paths)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"cannot resolve diff base ({error}): testing all focused checks", file=sys.stderr)
        checks, cache_probe = list(OPTIONAL_CHECKS), True
    if args.cache_only:
        print("yes" if cache_probe else "no")
    else:
        for check in checks:
            print(f".#checks.x86_64-linux.{check}")


if __name__ == "__main__":
    main()
