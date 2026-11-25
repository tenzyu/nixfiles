#!/usr/bin/env python3
"""Validate evaluated Jay TOML and the Jay keyboard and IME contract."""
import json
import sys
import tomllib
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
jay = tomllib.loads(data["jay"])
assert data["alacrittyOsc52"] == "OnlyCopy"
assert data["herdrReusesStock"] is True
assert data["skinAssociation"] == ["org.kde.ark.desktop"]
assert data["fileAssociation"] == ["dev.fileman.Files.desktop"]
keys = jay["shortcuts"]
assert jay["direct-scanout"] is True
assert jay["tearing"]["mode"] == "variant3"
assert jay["outputs"][0]["tearing"]["mode"] == "variant2"
assert data["presentationCcsScope"] is True
assert not jay.get("clients")
startup = [action["exec"] for action in jay["on-graphics-initialized"]]
ime = next(e for e in startup if isinstance(e, dict) and e.get("prog", "").endswith("/bin/fcitx5"))
watchers = [e for e in startup if isinstance(e, dict) and e.get("prog", "").endswith("/bin/wl-paste")]
assert not watchers
clipboard = [e for e in startup if isinstance(e, dict) and e.get("prog", "").endswith("cclip-start")]
assert len(clipboard) == 1 and clipboard[0]["privileged"] is True
assert clipboard[0]["args"] == []
assert ime["prog"].endswith("/bin/fcitx5") and ime["args"] == ["-r"]
assert ime["privileged"] is True and "tag" not in ime
# D-Bus environment must be imported before privileged clients start.
assert startup[0][0].endswith("/bin/dbus-update-activation-environment")
assert startup.index(clipboard[0]) < startup.index(ime)
assert len(startup) == 3
assert keys["logo-ctrl-i"]["exec"] == ime
assert keys["logo-i"]["exec"][0].endswith("/bin/fcitx5-remote")
assert keys["logo-i"]["exec"][1:] == ["-t"]
assert jay["vrr"]["mode"] == "never"
assert jay["xwayland"]["enabled"] is False
assert jay["outputs"][0]["mode"] == {"width": 1366, "height": 768}
assert jay["outputs"][0]["scale"] == 1.0
assert type(jay["outputs"][0]["scale"]) is float
assert keys["logo-q"] == "close"
assert keys["logo-ctrl-shift-q"] == "quit"
assert keys["logo-f"] == "toggle-fullscreen"
assert keys["logo-v"]["exec"] == ["cclip-picker"]
for key, mode in [("logo-space", "drun"), ("logo-r", "run")]:
    assert keys[key]["exec"][0].endswith("/bin/rofi")
    assert keys[key]["exec"][1:] == ["-show", mode, "-replace", "-terminal", "alacritty"]
for key, mode in [("logo-shift-r", "custom"), ("logo-shift-space", "desktop")]:
    assert keys[key]["exec"][0].endswith("/bin/jay-rofi-actions")
    assert keys[key]["exec"][1:] == [mode]
assert keys["logo-ctrl-shift-r"] == "reload-config-toml"
assert keys["logo-shift-v"] == "split-vertical"
assert keys["logo-Return"]["exec"].endswith("/bin/alacritty")
assert keys["logo-b"]["exec"] == "firefox"
assert keys["logo-o"]["exec"] == "osu-lazer"
assert jay["outputs"][0]["match"]["connector"] == "eDP-1"
assert keys["logo-shift-s"]["exec"]["privileged"] is True
assert "slurp" in keys["logo-shift-s"]["exec"]["shell"]
assert "grim" in keys["logo-shift-s"]["exec"]["shell"]
assert keys["Print"]["exec"]["privileged"] is True
assert {k for k, action in keys.items()
        if isinstance(action, dict) and isinstance(action.get("exec"), dict)
        and action["exec"].get("privileged")} == {"logo-ctrl-i", "logo-shift-s", "Print"}
assert sum(isinstance(e, dict) and e.get("privileged", False) for e in startup) == 2
assert keys["logo-Tab"] == "$next-workspace"
assert keys["logo-shift-Tab"] == "$previous-workspace"
assert jay["workspace-display-order"] == "sorted"
actions = jay["actions"]
assert actions["next-workspace"] == "$workspace-2"
assert actions["previous-workspace"] == "$workspace-10"
for i in range(1, 11):
    key = str(i % 10)
    assert keys["logo-" + key] == f"$workspace-{i}"
    assert keys["logo-shift-" + key] == [
        {"type": "move-to-workspace", "name": str(i)}, f"$workspace-{i}",
    ]
    assert actions[f"workspace-{i}"] == [
        {"type": "show-workspace", "name": str(i)},
        {"type": "define-action", "name": "next-workspace", "action": f"$workspace-{i % 10 + 1}"},
        {"type": "define-action", "name": "previous-workspace", "action": f"$workspace-{(i - 2) % 10 + 1}"},
    ]
print("Jay TOML, clipboard, screenshot and workspace cycle: PASS")
