#!/usr/bin/env python3
"""Select focused CI targets from the checked-out tree and its event base."""

import argparse
import os
import subprocess
import sys
from collections.abc import Callable, Collection, Iterable
from typing import NamedTuple

PYTHON_RUNTIME = (
    "assets/safety/python/default.nix",
    "assets/safety/python/safety_operations.py",
)
SHELL_PUBLISHER = (
    "assets/safety/shell/default.nix",
    "assets/safety/shell/native.py",
    "assets/safety/shell/operations.sh",
)
CACHE_PROBE = "splitcast-cache-probe"
OSU_LAB = "osu-lab"

# These files and component directories have known consumers in the focused set.
# A trailing slash means a directory; every other match is an exact Git path.
SCOPED_INPUTS = {
    "game-backup-minecraft": (
        *SHELL_PUBLISHER,
        "modules/10-foundations/game-backup-minecraft-check.nix",
        "modules/50-features/game-servers/_internal/minecraft-backup/",
        "modules/50-features/game-servers/commands.nix",
        "modules/50-features/game-servers/minecraft.nix",
    ),
    "home-authority-seal-vm": (
        "assets/home-authority/seal-acceptance.py",
        "modules/50-features/home/home-authority.nix",
        "modules/50-features/home/home-authority-seal-vm.nix",
    ),
    "home-authority-vm": (
        "assets/home-authority/",
        "modules/50-features/home/home-authority.nix",
        "modules/50-features/home/home-authority-vm.nix",
    ),
    "home-migration": (
        *PYTHON_RUNTIME,
        "assets/home-layout/",
        "modules/50-features/home/home-layout.nix",
        "modules/50-features/home/home-migration.nix",
    ),
    "nix-store-clean": (
        "assets/nix-store-clean/",
        "modules/50-features/nix/nix-store-clean.nix",
    ),
    "opencode-direnv": (
        "assets/opencode/",
        "modules/50-features/development/opencode-direnv.nix",
    ),
    "parsec-activation": (
        "assets/parsec-activation/",
        "assets/safety/shell/native.py",
        "modules/10-foundations/parsec-activation-check.nix",
        "modules/50-features/services/parsec.nix",
    ),
    "rtk-rewrites": (
        "assets/rtk/",
        "modules/50-features/development/rtk.nix",
    ),
    "safety-python": (
        *PYTHON_RUNTIME,
        *SHELL_PUBLISHER,
        "assets/safety/python/test_operations.py",
        "modules/10-foundations/safety-python-check.nix",
    ),
    "safety-shell": (
        *SHELL_PUBLISHER,
        "assets/safety/shell/test-operations.sh",
        "fixtures/contracts/safety-shell.md",
        "modules/10-foundations/safety-shell-check.nix",
    ),
    "steam-gaming": (
        "assets/steam-gaming/",
        "modules/50-features/gaming/steam.nix",
    ),
    CACHE_PROBE: (
        "modules/50-features/media/_internal/cache.nix",
        "scripts/ci/audit-splitcast-cache.sh",
    ),
    OSU_LAB: (
        "modules/50-features/gaming/neko5-osu-first.nix",
        "scripts/osu-performance/osu-lab.py",
        "scripts/osu-performance/test-osu-lab.py",
    ),
}
ALL_TARGETS = frozenset(SCOPED_INPUTS)
OPTIONAL_CHECKS = sorted(ALL_TARGETS - {CACHE_PROBE, OSU_LAB})

# Additional consumers of shared inputs do not make those inputs fully scoped.
SHARED_INPUTS = {
    "game-backup-minecraft": (
        "lib/service-layout.nix",
        "modules/50-features/game-servers/_internal/container.nix",
        "modules/50-features/game-servers/_internal/game.sh",
    ),
    CACHE_PROBE: (
        "modules/50-features/media/",
        "modules/50-features/nix/nix.nix",
    ),
}
DOCUMENTATION = {
    "AGENTS.md",
    "MEMORY.md",
    "README.md",
    "ROADMAP.md",
    "assets/home-layout/README.md",
    "assets/parsec-activation/README.md",
    "assets/safety/python/README.md",
    "assets/safety/shell/README.md",
    "docs/memory/provenance.json",
    "modules/50-features/game-servers/_internal/minecraft-backup/README.md",
    "scripts/osu-performance/README-display.md",
    "scripts/osu-performance/README-lab.md",
    "tools/adr02-rust/README.md",
}


class Selection(NamedTuple):
    checks: list[str]
    cache_probe: bool
    osu_lab: bool


def matches(path: str, patterns: tuple[str, ...]) -> bool:
    return any(path.startswith(pattern) if pattern.endswith("/") else path == pattern for pattern in patterns)


def selection(
    changed_paths: Iterable[str],
    *,
    non_regular_paths: Collection[str] = (),
    explain: Callable[[str], None] | None = None,
) -> Selection:
    targets: set[str] = set()
    for path in changed_paths:
        if path in DOCUMENTATION or (path.startswith("docs/") and path.endswith(".md")):
            if path in non_regular_paths:
                targets.update(ALL_TARGETS)
                reason = "executable or non-regular documentation path; all focused targets"
            else:
                reason = "documentation; always-on gates"
        elif path == "lib/tests.nix" or (
            path.startswith("modules/_internal/configurations/tests/") and path.endswith(".nix")
        ):
            reason = "framework fixture; always-on framework tests"
        else:
            scoped = {target for target, patterns in SCOPED_INPUTS.items() if matches(path, patterns)}
            additional = {target for target, patterns in SHARED_INPUTS.items() if matches(path, patterns)}
            if path.startswith("modules/50-features/") and path.endswith(".nix"):
                # Any feature declaration can add or change migration rules.
                additional.add("home-migration")

            if scoped:
                targets.update(scoped | additional)
                reason = ", ".join(sorted(scoped | additional))
            else:
                targets.update(ALL_TARGETS)
                reason = "unclassified or shared input; all focused targets"
                if additional:
                    reason += f" (known consumers: {', '.join(sorted(additional))})"

        if explain is not None:
            explain(f"{path!r}: {reason}")

    return Selection(
        [check for check in OPTIONAL_CHECKS if check in targets],
        CACHE_PROBE in targets,
        OSU_LAB in targets,
    )


def diff_paths(base: str) -> tuple[list[str], set[str]]:
    revision = subprocess.check_output(
        ["git", "rev-parse", "--verify", "--end-of-options", f"{base}^{{commit}}"]
    ).decode("ascii").strip()
    raw = subprocess.check_output([
        "git", "diff", "--raw", "-z", "--no-renames", "--no-ext-diff",
        "--no-relative", "--ignore-submodules=none", revision, "HEAD", "--",
    ])
    # --no-renames reports old and new names as separate delete/add records.
    # Raw modes distinguish ordinary docs from executables and symlinks.
    fields = raw.split(b"\0")
    if fields.pop() != b"" or len(fields) % 2:
        raise ValueError("incomplete Git diff record")
    paths = []
    non_regular_paths = set()
    for header, raw_path in zip(fields[::2], fields[1::2], strict=True):
        old_mode, new_mode, _, _, _ = header.removeprefix(b":").split()
        path = os.fsdecode(raw_path)
        paths.append(path)
        if {old_mode, new_mode} - {b"000000", b"100644"}:
            non_regular_paths.add(path)
    return paths, non_regular_paths


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base", default=os.environ.get("NIX_CHECK_BASE") or "HEAD^1",
        help="PR merge first parent or push event before SHA",
    )
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--cache-only", action="store_true")
    output.add_argument("--github-output", action="store_true")
    args = parser.parse_args()

    try:
        paths, non_regular_paths = diff_paths(args.base)
        result = selection(
            paths,
            non_regular_paths=non_regular_paths,
            explain=lambda reason: print(reason, file=sys.stderr),
        )
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"cannot resolve diff ({error}): testing all focused targets", file=sys.stderr)
        result = Selection(OPTIONAL_CHECKS, True, True)

    attrs = [f".#checks.x86_64-linux.{check}" for check in result.checks]
    cache = "yes" if result.cache_probe else "no"
    if args.github_output:
        print(f"checks={' '.join(attrs)}")
        print(f"cache_probe={cache}")
        print(f"osu_lab={'yes' if result.osu_lab else 'no'}")
    elif args.cache_only:
        print(cache)
    elif attrs:
        print("\n".join(attrs))


if __name__ == "__main__":
    main()
