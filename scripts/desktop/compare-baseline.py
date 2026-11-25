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
    # Only the measured presentation improvement and the approved launcher swap
    # may change the old baseline; check each replacement before normalization.
    assert "tearing" not in old_jay["outputs"][0]
    assert old_jay["tearing"]["mode"] == "variant3"
    old_jay["outputs"][0]["tearing"] = {"mode": "variant2"}
    old_keys, new_keys = old_jay["shortcuts"], new_jay["shortcuts"]
    old_app = old_keys["logo-space"]["exec"]
    assert old_app[0].endswith("/bin/tofi-drun")
    assert old_app[1:] == ["--drun-launch=true", "--terminal=alacritty"]
    for key, mode in [("logo-r", "run"), ("logo-shift-r", "custom"),
                      ("logo-shift-space", "desktop")]:
        old_exec = old_keys[key]["exec"]
        assert old_exec[0].endswith("/bin/jay-tofi-actions")
        assert old_exec[1:] == [mode]
    for key, mode in [("logo-space", "drun"), ("logo-r", "run")]:
        action = new_keys[key]
        argv = action["exec"]
        assert argv[0].endswith("/bin/rofi")
        assert argv[1:] == ["-show", mode, "-replace", "-terminal", "alacritty"]
        assert action == {"type": "exec", "exec": argv}
        old_keys[key] = action
    for key, mode in [("logo-shift-r", "custom"), ("logo-shift-space", "desktop")]:
        action = new_keys[key]
        argv = action["exec"]
        assert argv[0].endswith("/bin/jay-rofi-actions")
        assert argv[1:] == [mode]
        assert action == {"type": "exec", "exec": argv}
        old_keys[key] = action
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
        removed = Counter(["cliphist", "grimblast", "tofi"] +
                          (["cclip-picker"] if profile == "probe" else ["jay-tofi-actions"]))
        added = Counter(["rofi"] + (["jay-rofi-actions"] if profile == "primary" else []))
        old_packages, new_packages = Counter(old["homePackages"]), Counter(new["homePackages"])
        if (removed - old_packages or old_packages - new_packages != removed
                or new_packages - old_packages != added):
            raise AssertionError(
                f"{profile} direct package delta: removed={dict(old_packages - new_packages)}, "
                f"added={dict(new_packages - old_packages)}; "
                f"expected removed={dict(removed)}, added={dict(added)}"
            )
        print(f"{profile}: native policy unchanged; removed {dict(removed)}, added {dict(added)}")
    print("Complete parsed Jay TOML matches baseline plus eDP-1 variant2 and Rofi; direct package deltas as intended.")


if __name__ == "__main__":
    before, after = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
    compare(before, after)
