"""I-1 fixtures for the evaluated, packaged Home Manager activation fragments."""

import errno
import os
from pathlib import Path
import runpy
import stat
import subprocess
import sys
import tempfile
import unittest


CONFIG = b"decoder_software=0\nclient_decoder_h265=1\nclient_vsync=0\nclient_overlay_warnings=1\n"
ROW = (b"06cb,83d7 a:_00 b:_00 x:_00 y:_00 bk:_00 g:_00 s:_00 sl:_00 sr:_00 l:_00 r:_00 "
       b"du:_00 dr:_00 dd:_00 dl:_00 lyu:_00 lxr:_00 lyd:_00 lxl:_00 ryu:_00 rxr:_00 "
       b"ryd:_00 rxl:_00 tl:_00 tr:_00\n")


def write(path, data, mode=0o600):
    with path.open("xb") as stream:
        stream.write(data)
    path.chmod(mode)


def contents(path):
    # Observe bytes without invalidating the no-atime assertions.
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOATIME), "rb") as stream:
        return stream.read()


def metadata(path):
    info = path.lstat()
    return info.st_ino, info.st_mode, info.st_atime_ns, info.st_mtime_ns, info.st_ctime_ns


class Activation(unittest.TestCase):
    def setUp(self):
        root = self.enterContext(tempfile.TemporaryDirectory(prefix="parsec-fixture-"))
        self.home = Path(root).resolve() / "home with spaces"
        self.home.mkdir()
        self.parent = self.home / ".parsec"
        self.config = self.parent / "config.txt"
        self.mapping = self.parent / "gpmap.txt"
        self.legacy = self.parent / "gpmap.txt.tmp"

    def invoke(self, status=0, *, dry=False, fault=None, home=None):
        env = {**os.environ, "HOME": str(home or self.home)}
        env.pop("DRY_RUN", None)
        env.pop("PARSEC_FIXTURE_FAULT", None)
        if dry:
            env["DRY_RUN"] = ""  # HM keys on presence, not truthiness.
        if fault:
            env["PARSEC_FIXTURE_FAULT"] = fault
        result = subprocess.run([ACTIVATION], env=env, capture_output=True, text=True, timeout=12, umask=0o777)
        self.assertEqual(status, result.returncode, result.stderr)
        return result

    def test_dry_run_missing_and_occupied(self):
        result = self.invoke(dry=True)
        self.assertIn("parsec-activation.json", result.stdout)
        self.assertFalse(self.parent.exists())
        self.parent.mkdir()
        write(self.config, b"custom config")
        self.mapping.symlink_to("missing")
        write(self.legacy, b"legacy sentinel")
        paths = [self.config, self.mapping, self.legacy]
        before = [metadata(path) for path in paths]
        self.assertEqual("", self.invoke(dry=True).stderr)
        self.assertEqual(before, [metadata(path) for path in paths])

    def test_new_files_and_repeat_are_exact(self):
        self.assertEqual("", self.invoke().stderr)
        self.assertEqual(0o700, stat.S_IMODE(self.parent.stat().st_mode))
        self.assertEqual({"config.txt", "gpmap.txt"}, {path.name for path in self.parent.iterdir()})
        for path, expected in ((self.config, CONFIG), (self.mapping, ROW)):
            self.assertEqual(expected, contents(path))
            self.assertEqual(0o600, stat.S_IMODE(path.stat().st_mode))
            os.utime(path, (1, 2))
        before = [metadata(path) for path in (self.parent, self.config, self.mapping)]
        self.assertEqual("", self.invoke().stderr)
        self.assertEqual(before, [metadata(path) for path in (self.parent, self.config, self.mapping)])

    def test_identical_scope_preserves_other_mapping_rows(self):
        self.parent.mkdir(mode=0o755)
        write(self.config, CONFIG)
        # Includes a similar ID, CRLF, non-UTF-8 and an unterminated final row.
        data = b"06cb,83d70 other\r\n" + ROW.rstrip(b"\n") + b"\r\n0011,2233 \xff"
        write(self.mapping, data)
        write(self.legacy, b"do not touch")
        before = [metadata(path) for path in (self.mapping, self.legacy)]
        self.assertEqual("", self.invoke().stderr)
        self.assertEqual(before, [metadata(path) for path in (self.mapping, self.legacy)])
        self.assertEqual(data, contents(self.mapping))
        self.assertEqual(b"do not touch", contents(self.legacy))

    def test_existing_differences_warn_without_replacing(self):
        self.parent.mkdir()
        write(self.config, b"private config sentinel")
        for data in (b"", b"0001,0002 unrelated\n", b"06cb,83d7 custom\n", ROW + b"06cb,83d7\tduplicate\n"):
            with self.subTest(data=data):
                write(self.mapping, data)
                before = [metadata(path) for path in (self.config, self.mapping)]
                result = self.invoke()
                self.assertIn("existing config differs", result.stderr)
                self.assertIn("exactly one declared controller row", result.stderr)
                self.assertIn("independent backup", result.stderr)
                self.assertNotIn("private config sentinel", result.stderr)
                self.assertEqual(before, [metadata(path) for path in (self.config, self.mapping)])
                self.assertEqual(data, contents(self.mapping))
                self.mapping.unlink()
        write(self.mapping, ROW, 0o644)
        self.assertIn("file mode differs", self.invoke().stderr)
        self.assertEqual(0o644, stat.S_IMODE(self.mapping.stat().st_mode))

    def test_real_read_error_is_not_missing_or_empty(self):
        self.parent.mkdir()
        write(self.config, CONFIG)
        write(self.mapping, b"read denied", 0)
        write(self.legacy, b"legacy sentinel")
        before = [metadata(path) for path in (self.mapping, self.legacy)]
        self.assertIn("IOError: errno 13", self.invoke(74).stderr)
        self.assertEqual(before, [metadata(path) for path in (self.mapping, self.legacy)])
        self.mapping.chmod(0o600)
        self.assertEqual(b"read denied", contents(self.mapping))

    def test_unsafe_parent_does_not_write_through_symlink(self):
        target = self.home / "other"
        target.mkdir()
        self.parent.symlink_to(target)
        self.assertIn("Unsupported", self.invoke().stderr)
        self.assertEqual(target, self.parent.readlink())
        self.assertEqual([], list(target.iterdir()))
        alias = self.home.parent / "alias"
        alias.symlink_to(self.home)
        self.assertIn("Unsupported", self.invoke(home=alias).stderr)

    def test_special_entries_and_link_targets_not_touched(self):
        self.parent.mkdir()
        self.config.symlink_to("missing")
        self.mapping.mkdir()
        target = self.mapping / "unrelated"
        write(target, b"unrelated")
        self.legacy.symlink_to(target)
        for kind in ("directory", "dir-link", "fifo"):
            with self.subTest(kind=kind):
                before = [metadata(path) for path in (self.config, self.mapping, self.legacy, target)]
                self.assertEqual(2, self.invoke().stderr.count("not a user-owned regular file"))
                self.assertEqual(before, [metadata(path) for path in (self.config, self.mapping, self.legacy, target)])
                self.assertEqual(b"unrelated", contents(target))
                if kind == "directory":
                    self.mapping.rename(self.parent / "original-directory")
                    target = self.parent / "original-directory" / "unrelated"
                    self.mapping.symlink_to(target.parent)
                elif kind == "dir-link":
                    self.mapping.unlink()
                    os.mkfifo(self.mapping)

    def test_noncooperative_winner_at_commit(self):
        result = self.invoke(fault="race")
        self.assertIn("another writer created the final entry", result.stderr)
        self.assertEqual(b"other writer", contents(self.config))
        self.assertEqual(0o640, stat.S_IMODE(self.config.stat().st_mode))
        self.assertEqual(ROW, contents(self.mapping))
        self.assertEqual({"config.txt", "gpmap.txt"}, {path.name for path in self.parent.iterdir()})

    def test_new_mapping_leaves_legacy_temp_link_and_target_alone(self):
        self.parent.mkdir()
        sentinel = self.home / "unrelated"
        write(sentinel, b"keep this", mode=0o640)
        self.legacy.symlink_to(sentinel)
        before = [metadata(path) for path in (self.legacy, sentinel)]
        self.assertEqual("", self.invoke().stderr)
        self.assertEqual(ROW, contents(self.mapping))
        self.assertEqual(before, [metadata(path) for path in (self.legacy, sentinel)])
        self.assertEqual(sentinel, self.legacy.readlink())
        self.assertEqual(b"keep this", contents(sentinel))

    def test_parent_move_before_link_is_refused(self):
        self.assertIn("directory is not canonical or moved", self.invoke(fault="move-before").stderr)
        self.assertEqual([], list((self.home / "moved").iterdir()))
        self.assertTrue(self.parent.is_symlink())

    def test_parent_move_at_link_does_not_retarget_the_open_dirfd(self):
        result = self.invoke(75, fault="move-at-link")
        self.assertIn("OutcomeUnknown", result.stderr)
        self.assertEqual(CONFIG, contents(self.home / "moved" / "config.txt"))
        self.assertFalse((self.home / "new-parent" / "config.txt").exists())

    def test_unsupported_and_failed_file_flush_do_not_publish(self):
        self.assertIn("filesystem does not support unnamed staging", self.invoke(fault="no-tmpfile").stderr)
        self.assertEqual([], list(self.parent.iterdir()))
        self.assertIn("no file published", self.invoke(74, fault="file-flush").stderr)
        self.assertEqual([], list(self.parent.iterdir()))

    def test_directory_flush_failure_reports_visible_final(self):
        self.assertIn("OutcomeUnknown: final may be visible", self.invoke(75, fault="dir-flush").stderr)
        self.assertEqual(CONFIG, contents(self.config))
        before = metadata(self.config)
        self.assertFalse(self.mapping.exists())
        self.assertEqual("", self.invoke().stderr)
        self.assertEqual(before, metadata(self.config))


def inject():
    """Use actual kernel publication, with a deterministic writer/failure at its boundary."""
    script, *args = sys.argv[2:]
    fault = os.environ["PARSEC_FIXTURE_FAULT"]

    def move_parent():
        home = Path(os.environ["HOME"])
        parent = home / ".parsec"
        parent.rename(home / "moved")
        (home / "new-parent").mkdir()
        parent.symlink_to(home / "new-parent")

    def hook(event, payload):
        if fault == "race" and event == "os.link" and payload[1] == "config.txt":
            # A different process does not cooperate with any activation check.
            subprocess.run([sys.executable, "-I", "-c", """
import os
from pathlib import Path
p = Path(os.environ['HOME']) / '.parsec' / 'config.txt'
with p.open('xb') as f:
    f.write(b'other writer')
p.chmod(0o640)
"""], check=True)
        elif fault == "no-tmpfile" and event == "open" and payload[2] & os.O_TMPFILE == os.O_TMPFILE:
            raise OSError(errno.EOPNOTSUPP, os.strerror(errno.EOPNOTSUPP))
        elif fault in ("file-flush", "dir-flush", "move-before") and event == "subprocess.Popen" and payload[1][-2] == "fsync":
            if stat.S_ISDIR(os.fstat(int(payload[1][-1])).st_mode) == (fault == "dir-flush"):
                if fault == "move-before":
                    move_parent()
                else:
                    raise OSError(errno.EIO, os.strerror(errno.EIO))
        elif fault == "move-at-link" and event == "os.link":
            move_parent()

    sys.addaudithook(hook)
    sys.argv = [script, *args]
    runpy.run_path(script, run_name="__main__")


if __name__ == "__main__":
    if sys.argv[1] == "--inject":
        inject()
    else:
        ACTIVATION = sys.argv.pop(1)
        unittest.main(verbosity=2)
