"""Exercise process accounting without reading a live session."""
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

process_pss = runpy.run_path(str(Path(__file__).with_name("memory-snapshot.py")))["process_pss"]


class ProcessAccounting(unittest.TestCase):
    def test_unreadable_and_non_utf8_processes(self):
        with tempfile.TemporaryDirectory() as root:
            proc = Path(root)
            for pid in ("1", "2", "3", "4"):
                (proc / pid).mkdir()
            (proc / "1/smaps_rollup").write_text("Pss: 20 kB\nPss_Anon: 5 kB\n")
            (proc / "1/comm").write_bytes(b"game-\xff\n")
            (proc / "2/smaps_rollup").write_text("Rss: 10 kB\n")
            (proc / "3/smaps_rollup").write_text("Pss: 3 kB\n")
            self.assertEqual(process_pss(proc), ([{"pid": 1, "comm": "game-\ufffd", "pss_kib": 20,
                                                   "pss_anon_kib": 5}], 3))

    def test_directory_identity_survives_path_replacement(self):
        with tempfile.TemporaryDirectory() as root:
            proc = Path(root) / "proc"
            proc.mkdir()
            pid = proc / "1"
            pid.mkdir()
            (pid / "smaps_rollup").write_text("Pss: 20 kB\n")
            (pid / "comm").write_text("original\n")
            original_open = os.open
            original_read = Path.read_text

            def replace():
                pid.rename(Path(root) / "old")
                pid.mkdir()
                (pid / "comm").write_text("replacement\n")

            def open_before_comm(path, *args, **kwargs):
                if path == "comm":
                    replace()
                return original_open(path, *args, **kwargs)

            def read_before_comm(path, *args, **kwargs):
                if path == pid / "comm":
                    replace()
                return original_read(path, *args, **kwargs)

            with patch.object(os, "open", side_effect=open_before_comm), \
                    patch.object(Path, "read_text", new=read_before_comm):
                rows, unavailable = process_pss(proc)
            self.assertEqual(rows, [{"pid": 1, "comm": "original", "pss_kib": 20}])
            self.assertEqual(unavailable, 0)


if __name__ == "__main__":
    unittest.main()
