#!/usr/bin/env python3
"""Stacked change gate: protect the accepted desktop and its package identities.

This compares evaluated declarations, not measured performance or closures.
The only allowed native baseline policy delta is compressed profiling.
"""
from collections import Counter
import json
from pathlib import Path
import sys
import tomllib

PROFILING = "sysctl.vm.mem_profiling=1,compressed"


def compare(before, after):
    if tomllib.loads(before["jay"]) != tomllib.loads(after["jay"]):
        raise AssertionError("Protected Jay TOML changed")
    for profile in ("primary", "probe"):
        old = before[profile]
        new = after[profile]
        policy = dict(new["policy"])
        params = policy["kernelParams"]
        old_params = old["policy"]["kernelParams"]
        expected_count = 1 if PROFILING not in old_params else 0
        if params.count(PROFILING) != 1:
            raise AssertionError(f"{profile}: expected exactly one compressed profiling parameter")
        if expected_count:
            policy["kernelParams"] = [p for p in params if p != PROFILING]
        if old["policy"] != policy:
            changed = sorted(k for k in old["policy"].keys() | policy.keys()
                             if old["policy"].get(k) != policy.get(k))
            raise AssertionError(f"{profile}: protected policy changed: {changed}")
        old_packages = Counter(old["homePackages"])
        new_packages = Counter(new["homePackages"])
        if old_packages != new_packages:
            raise AssertionError(
                f"{profile}: package selection changed: "
                f"removed={dict(old_packages - new_packages)}, "
                f"added={dict(new_packages - old_packages)}"
            )
        print(f"{profile}: protected policy and direct home package names unchanged")
    print("Protected Jay TOML unchanged; source equivalence only.")


if __name__ == "__main__":
    before, after = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
    compare(before, after)
