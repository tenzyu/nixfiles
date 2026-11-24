#!/usr/bin/env python3
"""Offline routing and menu tests; no compositor, clipboard or history access."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class ClipboardIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ, PATH=f"{self.root}:{os.environ['PATH']}",
                        XDG_RUNTIME_DIR=str(self.root), XDG_CURRENT_DESKTOP="jay",
                        WAYLAND_DISPLAY="wayland-1", FIXTURE=str(self.root))
        self.stub("wl-copy-real", "cat")
        self.shim = self.root / "shim"
        self.shim.write_text((HERE / "herdr-wl-copy.sh").read_text()
                             .replace("@HERDR@", str(Path(sys.executable).resolve()))
                             .replace("@READLINK@", "readlink")
                             .replace("@WL_COPY@", str(self.root / "wl-copy-real")))
        self.stub("richclip", """python3 - "$@" <<'PYTHON'
import json, os, sys
from pathlib import Path
root = Path(os.environ["FIXTURE"])
args = sys.argv[1:]
with (root / "calls").open("a") as out:
    out.write(json.dumps(args) + "\\n")
if args[0] == "list":
    if os.environ.get("LIST_FAIL"):
        sys.exit(1)
    items = json.loads((root / "items").read_text())
    if "--limit" in args:
        items = items[:int(args[args.index("--limit") + 1])]
    print(json.dumps(items))
elif args[0] == "restore":
    (root / "restored").write_text(args[1])
PYTHON""")
        self.stub("tofi", """cat > "$FIXTURE/menu"
case "${PICK:-first}" in
  cancel) exit 1 ;;
  invalid) echo "unknown invalid" ;;
  older)
    if grep -q '^__all__ ' "$FIXTURE/menu"; then
      grep '^__all__ ' "$FIXTURE/menu"
    else
      tail -n 1 "$FIXTURE/menu"
    fi ;;
  *) head -n 1 "$FIXTURE/menu" ;;
esac""")
        self.stub("notify-send", 'printf "%s\n" "$*" >> "$FIXTURE/notices"')

    def stub(self, name, script):
        path = self.root / name
        path.write_text("#!/bin/bash\n" + script + "\n")
        path.chmod(0o755)

    def shim_call(self, args, **env):
        return subprocess.run(["bash", str(self.shim), *args], input="test",
                              text=True, capture_output=True, env=dict(self.env, **env))

    def picker(self, count, **env):
        (self.root / "items").write_text(json.dumps([
            {"id": f"id{i}", "label": f"日本語 {i}\nnext",
             "formats": [{"mime": "text/plain"}]} for i in range(count)
        ]))
        return subprocess.run(["bash", "-euo", "pipefail", str(HERE / "richclip-picker.sh")],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_scoped_osc52_fallback(self):
        args = ["--type", "text/plain;charset=utf-8"]
        result = self.shim_call(args)
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        for result in (self.shim_call(args, XDG_CURRENT_DESKTOP="other"),
                       self.shim_call(args, WAYLAND_DISPLAY=""),
                       self.shim_call(["--type", "image/png"])):
            self.assertEqual((result.returncode, result.stdout), (0, "test"))
        # A normal pane process using the exact same args must not be masked.
        self.shim.write_text(self.shim.read_text().replace(
            str(Path(sys.executable).resolve()), "/not-herdr"))
        result = self.shim_call(args)
        self.assertEqual((result.returncode, result.stdout), (0, "test"))

    def test_recent_restore(self):
        result = self.picker(150)
        self.assertEqual(result.returncode, 0, result.stderr)
        menu = (self.root / "menu").read_text().splitlines()
        self.assertEqual(len(menu), 129)
        self.assertEqual(menu[0], "id0 日本語 0 next")
        self.assertEqual(menu[-1], "__all__ Show all history")
        self.assertEqual((self.root / "restored").read_text(), "id0")

    def test_all_history_remains_accessible(self):
        result = self.picker(150, PICK="older")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "restored").read_text(), "id149")
        calls = [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]
        self.assertEqual(calls[:2], [["list", "--json", "--limit", "129"], ["list", "--json"]])

    def test_empty_and_error(self):
        self.assertEqual(self.picker(0).returncode, 0)
        self.assertIn("No saved clipboard history", (self.root / "notices").read_text())
        self.assertEqual(self.picker(1, LIST_FAIL="1").returncode, 1)
        self.assertIn("Could not load history", (self.root / "notices").read_text())
        self.assertFalse((self.root / "restored").exists())

    def test_cancel_and_invalid_selection(self):
        self.assertEqual(self.picker(1, PICK="cancel").returncode, 0)
        self.assertEqual(self.picker(1, PICK="invalid").returncode, 1)
        self.assertFalse((self.root / "restored").exists())


if __name__ == "__main__":
    unittest.main()
