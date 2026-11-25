#!/usr/bin/env python3
"""Compare stack-parent source declarations, permitting only reviewed deltas."""
from collections import Counter
import json
from pathlib import Path
import sys
import tomllib

KERNEL_DELTA = {
    "zswap.enabled=1", "zswap.compressor=zstd", "zswap.max_pool_percent=25",
    "zswap.shrinker_enabled=1", "sysctl.vm.mem_profiling=never",
}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def compare_jay(before, after):
    old, new = (tomllib.loads(x) for x in (before, after))
    a, b = old["shortcuts"], new["shortcuts"]
    require(a["logo-Return"]["exec"].endswith("/bin/alacritty"), "old terminal")
    require(b["logo-Return"]["exec"].endswith("/bin/foot"), "new terminal")
    a["logo-Return"]["exec"] = b["logo-Return"]["exec"]
    for key, mode in (("logo-space", "drun"), ("logo-r", "run")):
        launch = a[key]["exec"]
        require(launch[1:] == ["-show", mode, "-replace", "-terminal", "alacritty"],
                f"{key}: unexpected old Rofi launch")
        launch[-1] = "foot"
    for key, mode in (("logo-shift-space", "desktop"), ("logo-shift-r", "custom")):
        prev, curr = a[key]["exec"], b[key]["exec"]
        require(prev[0].endswith("/bin/jay-rofi-actions") and
                curr[0].endswith("/bin/jay-rofi-actions") and prev[1:] == [mode],
                f"{key}: unexpected action owner")
        expected = [mode, "foot"] if mode == "custom" else [mode]
        require(curr[1:] == expected, f"{key}: unexpected new action")
        a[key]["exec"] = curr
    require(old == new, "unexpected Jay TOML delta outside terminal routing")


def compare(before, after):
    compare_jay(before["jay"], after["jay"])
    for profile in ("primary", "probe"):
        old, new = before[profile], after[profile]
        policy = dict(new["policy"])
        params = policy["kernelParams"]
        previous = old["policy"]["kernelParams"]
        require(all(params.count(p) == 1 for p in KERNEL_DELTA),
                f"{profile}: missing or duplicate memory policy")
        require(Counter(params) == Counter(previous) + Counter(KERNEL_DELTA),
                f"{profile}: unexpected kernel command-line delta")
        policy["kernelParams"] = previous
        mime = dict(policy["mime"])
        require(old["policy"]["mime"]["inode/directory"] == ["dev.fileman.Files.desktop"] and
                mime["inode/directory"] == ["thunar.desktop"],
                f"{profile}: unexpected file manager association")
        mime["inode/directory"] = old["policy"]["mime"]["inode/directory"]
        policy["mime"] = mime
        require(old["policy"] == policy, f"{profile}: protected native policy changed")
        old_names, new_names = (Counter(s["homePackages"]) for s in (old, new))
        require(old_names - new_names == Counter({"alacritty": 1, "fileman": 1}) and
                new_names - old_names == Counter({"foot": 1}),
                f"{profile}: unexpected direct package delta: "
                f"{dict(old_names-new_names)} -> {dict(new_names-old_names)}")
        allowed = {"alacritty", "foot", "fileman", "firefox"}
        if profile == "primary":
            allowed.add("jay-rofi-actions")
        def protected(s):
            return Counter((p["name"], p["drv"]) for p in s["homePackageEntries"]
                           if p["name"] not in allowed)
        require(protected(old) == protected(new),
                f"{profile}: unrelated package derivation changed")
        print(f"{profile}: only approved terminal, file manager, Firefox and resource-policy deltas")
    print("Protected source contract: PASS; physical behavior remains unverified.")


if __name__ == "__main__":
    before, after = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
    compare(before, after)
