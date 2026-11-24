#!/usr/bin/env python3
"""Validate evaluated Jay TOML and the Jay keyboard and IME contract."""
import json
import sys
import tomllib
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
jay = tomllib.loads(data["jay"])
keys = jay["shortcuts"]
assert jay["direct-scanout"] is True
assert jay["tearing"]["mode"] == "variant3"
assert not jay.get("clients")
ime = jay["on-graphics-initialized"][1]["exec"]
assert ime["prog"].endswith("/bin/fcitx5") and ime["args"] == ["-r"]
assert ime["privileged"] is True and "tag" not in ime
assert keys["logo-ctrl-i"]["exec"] == ime
assert keys["logo-i"]["exec"][0].endswith("/bin/fcitx5-remote")
assert keys["logo-i"]["exec"][1:] == ["-t"]
assert jay["vrr"]["mode"] == "never"
assert jay["xwayland"]["enabled"] is False
assert jay["outputs"][0]["mode"] == {"width": 1366, "height": 768}
assert jay["outputs"][0]["scale"] == 1.0
assert keys["logo-q"] == "close"
assert keys["logo-ctrl-shift-q"] == "quit"
assert keys["logo-f"] == "toggle-fullscreen"
for i in range(1, 11):
    key = str(i % 10)
    assert keys["logo-" + key] == {"type": "show-workspace", "name": str(i)}
    assert keys["logo-shift-" + key] == [
        {"type": "move-to-workspace", "name": str(i)},
        {"type": "show-workspace", "name": str(i)},
    ]
print("Jay TOML and 10 workspace key pairs: PASS")
