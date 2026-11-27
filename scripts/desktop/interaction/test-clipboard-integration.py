#!/usr/bin/env python3
"""Offline clipboard and launcher routing tests; never access a live session."""
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
                        XDG_RUNTIME_DIR=str(self.root), XDG_DATA_HOME=str(self.root / 'data'),
                        XDG_CURRENT_DESKTOP="jay", WAYLAND_DISPLAY="wayland-1",
                        FIXTURE=str(self.root))
        self.stub("wl-copy-real", "cat")
        self.shim = self.root / "shim"
        self.shim.write_text((HERE / "herdr-wl-copy.sh").read_text()
                             .replace("@HERDR@", str(Path(sys.executable).resolve()))
                             .replace("@READLINK@", "readlink")
                             .replace("@WL_COPY@", str(self.root / "wl-copy-real")))
        self.stub("cclip", """[[ "$*" == 'list rowid,preview' ]] || exit 7
[[ -z "${LIST_FAIL:-}" ]] || exit 1
cat "$FIXTURE/items" """)
        self.stub("cclipd", 'printf "%s\\n" "$@" > "$FIXTURE/daemon-args"')
        self.stub("rofi", """cat > "$FIXTURE/menu"
case "${PICK:-first}" in
  cancel) exit 1 ;;
  invalid) printf '999\\tinvalid\\n' ;;
  last) tail -n 1 "$FIXTURE/menu" ;;
  *) head -n 1 "$FIXTURE/menu" ;;
esac""")
        self.stub("jay", """printf '%s\\n' "$@" > "$FIXTURE/jay-calls"
[[ -z "${RESTORE_FAIL:-}" ]]""")
        self.stub("alacritty", 'printf "%s\\n" "$@" > "$FIXTURE/terminal"')
        self.stub("notify-send", 'printf "%s\\n" "$*" >> "$FIXTURE/notices"')

    def stub(self, name, script):
        path = self.root / name
        path.write_text("#!/bin/bash\n" + script + "\n")
        path.chmod(0o755)

    def shim_call(self, args, **env):
        return subprocess.run(["bash", str(self.shim), *args], input="test",
                              text=True, capture_output=True, env=dict(self.env, **env))

    def picker(self, rows, **env):
        (self.root / "items").write_text(rows)
        return subprocess.run(["bash", "-euo", "pipefail", str(HERE / "cclip-picker.sh")],
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

    def test_restore(self):
        result = self.picker("1\t日本語\n2\tabcdefghijklmnopqrstuvwxyz1234\n", PICK="last")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "jay-calls").read_text(), "run-privileged\ncclip\ncopy\n2\n")

    def test_cancel_and_invalid(self):
        self.assertEqual(self.picker("1\ttext\n", PICK="cancel").returncode, 0)
        self.assertEqual(self.picker("1\ttext\n", PICK="invalid").returncode, 1)
        self.assertFalse((self.root / "jay-calls").exists())

    def test_empty_and_failure(self):
        self.assertEqual(self.picker("").returncode, 0)
        self.assertEqual(self.picker("1\ttext\n", LIST_FAIL="1").returncode, 1)
        self.assertFalse((self.root / "jay-calls").exists())
        self.assertEqual(self.picker("1\ttext\n", RESTORE_FAIL="1").returncode, 1)

    def test_private_daemon_directory(self):
        result = subprocess.run(["bash", "-euo", "pipefail", str(HERE / "cclip-start.sh")],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "data" / "cclip").stat().st_mode & 0o777, 0o700)
        args = (self.root / "daemon-args").read_text().splitlines()
        self.assertEqual(args[:4], ["-c", "512", "-P", "160"])
        self.assertNotIn("-p", args)
        self.assertNotIn("-S", args)

    def test_screenshot_commit_boundary(self):
        self.stub("slurp", '[[ "${CANCEL:-0}" != 1 ]] || exit 1; printf "0,0 20x20"')
        self.stub("grim", 'printf "image"; [[ "${CAPTURE_FAIL:-0}" != 1 ]]')
        self.stub("wl-copy", '[[ "$*" == "--type image/png" ]] || exit 7; cat > "$FIXTURE/selection"')
        selection = self.root / "selection"
        selection.write_text("incumbent")
        def capture(mode, **env):
            return subprocess.run(["bash", str(HERE / "jay-screenshot.sh"), mode],
                                  env=dict(self.env, **env), capture_output=True)
        self.assertEqual(capture("area", CANCEL="1").returncode, 0)
        self.assertEqual(selection.read_text(), "incumbent")
        for mode in ("area", "full"):
            self.assertNotEqual(capture(mode, CAPTURE_FAIL="1").returncode, 0)
            self.assertEqual(selection.read_text(), "incumbent")
            self.assertEqual(list(self.root.glob("jay-screenshot.*")), [])
        for mode in ("area", "full"):
            self.assertEqual(capture(mode).returncode, 0)
            self.assertEqual(selection.read_text(), "image")
            self.assertEqual(list(self.root.glob("jay-screenshot.*")), [])

    def test_launcher_modes(self):
        script = self.root / "actions.sh"
        script.write_text((HERE / "rofi-actions.sh").read_text())
        for mode, env in [
            ("custom", {}),
            ("desktop", {}),
        ]:
            result = subprocess.run(["bash", "-euo", "pipefail", str(script), mode],
                                    env=dict(self.env, **env), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--working-directory", (self.root / "terminal").read_text())
        self.assertEqual((self.root / "jay-calls").read_text(), "control-center\n")


if __name__ == "__main__":
    unittest.main()
