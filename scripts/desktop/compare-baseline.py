#!/usr/bin/env python3
"""One-time source-level equivalence gate; package lists are not runtime closures."""
from collections import Counter
import json
from pathlib import Path
import sys
import tomllib


def compare(before, after):
    old_jay = tomllib.loads(before["jay"])
    new_jay = tomllib.loads(after["jay"])
    if old_jay != new_jay:
        changed = sorted(k for k in old_jay.keys() | new_jay.keys()
                         if old_jay.get(k) != new_jay.get(k))
        raise AssertionError(f"Jay TOML semantics changed: {changed}")
    assert type(new_jay["outputs"][0]["scale"]) is float
    for profile in ("primary", "probe"):
        old, new = before[profile], after[profile]
        changed = sorted(k for k in old["policy"].keys() | new["policy"].keys()
                         if old["policy"].get(k) != new["policy"].get(k))
        if changed:
            raise AssertionError(f"{profile} native policy changed: {changed}")
        removed = Counter(["cliphist", "grimblast"] +
                          (["cclip-picker"] if profile == "probe" else []))
        old_packages, new_packages = Counter(old["homePackages"]), Counter(new["homePackages"])
        if removed - old_packages or old_packages - new_packages != removed or new_packages - old_packages:
            raise AssertionError(
                f"{profile} direct package delta: removed={dict(old_packages - new_packages)}, "
                f"added={dict(new_packages - old_packages)}; expected removed={dict(removed)}"
            )
        print(f"{profile}: native policy unchanged; removed {dict(removed)}")
    print("Complete parsed Jay TOML unchanged; direct package deltas as intended.")


if __name__ == "__main__":
    before, after = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
    compare(before, after)
