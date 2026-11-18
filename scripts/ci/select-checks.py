#!/usr/bin/env python3
"""Select affected Nix checks without treating full flake check as a PR gate."""

import argparse
import subprocess
from pathlib import PurePosixPath

OPTIONAL_CHECKS = (
    "home-migration",
    "nix-store-clean",
    "opencode-direnv",
    "rtk-rewrites",
)


def selection(changed_paths: list[str]) -> tuple[list[str], bool]:
    checks: set[str] = set()
    cache_probe = False
    for raw in changed_paths:
        path = PurePosixPath(raw).as_posix()
        if path in ("flake.lock", "flake.nix"):
            checks.update(OPTIONAL_CHECKS)
            cache_probe = True
        if path.startswith(("modules/50-features/home/", "assets/home-layout/")):
            checks.add("home-migration")
        if path == "modules/50-features/nix/nix-store-clean.nix" or path.startswith("assets/nix-store-clean/"):
            checks.add("nix-store-clean")
        if path == "modules/50-features/development/opencode-direnv.nix" or path.startswith("assets/opencode/"):
            checks.add("opencode-direnv")
        if path == "modules/50-features/development/rtk.nix" or path.startswith("assets/rtk/"):
            checks.add("rtk-rewrites")
        if (path.startswith("modules/50-features/media/") or path in (
            "modules/50-features/nix/nix.nix",
            "scripts/ci/audit-splitcast-cache.sh",
        )):
            cache_probe = True
    return sorted(checks), cache_probe


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="HEAD^", help="First parent of checked-out PR merge commit, or previous main commit")
    parser.add_argument("--cache-only", action="store_true")
    args = parser.parse_args()

    paths = subprocess.check_output(
        ["git", "diff", "--name-only", args.base, "HEAD"], text=True
    ).splitlines()
    checks, cache_probe = selection(paths)
    if args.cache_only:
        print("yes" if cache_probe else "no")
    else:
        for check in checks:
            print(f".#checks.x86_64-linux.{check}")


if __name__ == "__main__":
    main()
