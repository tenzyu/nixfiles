#!/usr/bin/env python3
"""Stacked change gate: protect the accepted desktop and its package identities.

This compares evaluated declarations, not measured performance or closures.
Only the explicit kernel swap-policy arguments may differ.
"""
from collections import Counter
import json
from pathlib import Path
import sys
import tomllib

KERNEL_DELTA = {
    "zswap.enabled=1", "zswap.compressor=lz4", "zswap.max_pool_percent=25",
    "zswap.shrinker_enabled=1",
}


def compare(before, after):
    if tomllib.loads(before["jay"]) != tomllib.loads(after["jay"]):
        raise AssertionError("Protected Jay TOML changed")
    for profile in ("primary", "probe"):
        old = before[profile]
        new = after[profile]
        policy = dict(new["policy"])
        params = policy["kernelParams"]
        old_params = old["policy"]["kernelParams"]
        if Counter(params) != Counter(old_params) + Counter(KERNEL_DELTA):
            raise AssertionError(f"{profile}: unexpected kernel parameter delta")
        policy["kernelParams"] = old_params
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
        if Counter(old["homePackageDrvs"]) != Counter(new["homePackageDrvs"]):
            raise AssertionError(f"{profile}: direct home package derivations changed")
        print(f"{profile}: protected policy and direct home package derivations unchanged")
    print("Protected Jay TOML unchanged; source equivalence only.")


if __name__ == "__main__":
    before, after = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
    compare(before, after)
