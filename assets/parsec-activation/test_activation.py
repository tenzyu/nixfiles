"""I-1 fixtures for the packaged Home Manager activation and review command."""

import errno
import json
import os
from pathlib import Path
import runpy
import stat
import subprocess
import sys
import tempfile
import unittest


SEED = {
    "decoder_software": {"value": 0},
    "client_decoder_h265": {"value": 1},
    "client_vsync": {"value": 0},
    "client_overlay_warnings": {"value": 1},
}
LEGACY_INPUT = b"client_vsync=1\nother=private legacy sentinel\n"
APP_CONFIG = b'''{
    "decoder_software": {"value": 0},
    "client_decoder_h265": {"value": 1},
    "client_vsync": {"value": 0},
    "client_overlay_warnings": {"value": 1},
    "unrelated": {"value": "private JSON sentinel"}
}\n'''
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
        self.config = self.parent / "config.json"
        self.legacy_config = self.parent / "config.txt"
        self.mapping = self.parent / "gpmap.txt"
        self.legacy = self.parent / "gpmap.txt.tmp"

    def invoke(self, status=0, *, dry=False, fault=None, home=None, review=False):
        env = {**os.environ, "HOME": str(home or self.home)}
        env.pop("DRY_RUN", None)
        env.pop("PARSEC_FIXTURE_FAULT", None)
        if dry:
            env["DRY_RUN"] = ""  # HM keys on presence, not truthiness.
        if fault:
            env["PARSEC_FIXTURE_FAULT"] = fault
        result = subprocess.run([REVIEW if review else ACTIVATION], env=env, capture_output=True, text=True,
                                timeout=12, umask=0o777)
        self.assertEqual(status, result.returncode, result.stdout + result.stderr)
        return result

    def test_dry_run_missing_and_occupied(self):
        result = self.invoke(dry=True)
        self.assertIn("parsec-activation.json", result.stdout)
        self.assertFalse(self.parent.exists())
        self.parent.mkdir()
        write(self.config, APP_CONFIG)
        write(self.legacy_config, LEGACY_INPUT)
        self.mapping.symlink_to("missing")
        write(self.legacy, b"legacy sentinel")
        paths = [self.config, self.legacy_config, self.mapping, self.legacy]
        before = [metadata(path) for path in paths]
        self.assertEqual("", self.invoke(dry=True).stderr)
        self.assertEqual(before, [metadata(path) for path in paths])

    def test_new_files_and_repeat_are_exact(self):
        self.assertIn("no Parsec files to review", self.invoke(1, review=True).stdout)
        self.assertFalse(self.parent.exists())
        self.assertEqual("", self.invoke().stderr)
        self.assertEqual(0o700, stat.S_IMODE(self.parent.stat().st_mode))
        self.assertEqual({"config.json", "gpmap.txt"}, {path.name for path in self.parent.iterdir()})
        seed_bytes = contents(self.config)
        self.assertEqual(SEED, json.loads(seed_bytes))
        self.assertEqual(ROW, contents(self.mapping))
        for path in (self.config, self.mapping):
            self.assertEqual(0o600, stat.S_IMODE(path.stat().st_mode))
            os.utime(path, (1, 2))
        before = [metadata(path) for path in (self.parent, self.config, self.mapping)]
        self.assertEqual(2, self.invoke().stderr.count("existing entry preserved; skipped the seed"))
        review = self.invoke(review=True)
        self.assertIn("config.json: client_vsync=0 [present]", review.stdout)
        self.assertIn("config.txt: missing", review.stdout)
        self.assertIn("declared controller row for 06cb,83d7 present exactly once", review.stdout)
        self.assertEqual("", review.stderr)
        self.assertEqual(before, [metadata(path) for path in (self.parent, self.config, self.mapping)])
        self.assertEqual(seed_bytes, contents(self.config))
        self.assertFalse(self.legacy_config.exists())

    def test_identical_scope_preserves_other_mapping_rows(self):
        self.parent.mkdir(mode=0o755)
        write(self.config, APP_CONFIG)
        # Includes a similar ID, CRLF, non-UTF-8 and an unterminated final row.
        data = b"06cb,83d70 other\r\n" + ROW.rstrip(b"\n") + b"\r\n0011,2233 \xff"
        write(self.mapping, data)
        write(self.legacy, b"do not touch")
        before = [metadata(path) for path in (self.mapping, self.legacy)]
        self.assertEqual(2, self.invoke().stderr.count("existing entry preserved; skipped the seed"))
        self.assertIn("declared controller row for 06cb,83d7 present exactly once", self.invoke(review=True).stdout)
        self.assertEqual(before, [metadata(path) for path in (self.mapping, self.legacy)])
        self.assertEqual(data, contents(self.mapping))
        self.assertEqual(b"do not touch", contents(self.legacy))

    def test_existing_differences_are_reported_by_review_only(self):
        self.parent.mkdir()
        config_data = b'{"unrelated": {"value": "private config sentinel"}}'
        write(self.config, config_data)
        for data in (b"", b"0001,0002 unrelated\n", b"06cb,83d7 custom\n", ROW + b"06cb,83d7\tduplicate\n"):
            with self.subTest(data=data):
                write(self.mapping, data)
                before = [metadata(path) for path in (self.config, self.mapping)]
                result = self.invoke()
                self.assertEqual(2, result.stderr.count("existing entry preserved; skipped the seed"))
                review = self.invoke(1, review=True)
                self.assertIn("config.json: client_vsync=0 [missing]", review.stdout)
                self.assertIn("expected one exact row", review.stdout)
                self.assertNotIn("private config sentinel", review.stdout + review.stderr)
                self.assertEqual(before, [metadata(path) for path in (self.config, self.mapping)])
                self.assertEqual(config_data, contents(self.config))
                self.assertEqual(data, contents(self.mapping))
                self.mapping.unlink()
        write(self.mapping, ROW, 0o644)
        self.assertIn("gpmap.txt: mode 0644, expected 0600", self.invoke(1, review=True).stdout)
        self.assertEqual(0o644, stat.S_IMODE(self.mapping.stat().st_mode))

    def test_review_legacy_differences_and_duplicate_rows_without_disclosing_data(self):
        self.parent.mkdir()
        config = b"decoder_software=1\nclient_vsync=0\nclient_vsync=1\nother=private txt sentinel\n"
        mapping = b"0001,0002 private mapping sentinel\n" + ROW + b"06cb,83d7 private target row\n"
        write(self.legacy_config, config)
        write(self.mapping, mapping, 0o644)
        paths = (self.parent, self.legacy_config, self.mapping)
        before = [metadata(path) for path in paths]
        result = self.invoke(1, review=True)
        self.assertIn("decoder_software=0 [different value]", result.stdout)
        self.assertIn("client_vsync=0 [multiple assignments]", result.stdout)
        self.assertIn("client_overlay_warnings=1 [missing]", result.stdout)
        self.assertIn("existing legacy input suppresses the config.json seed", result.stdout)
        self.assertIn("2 row(s) for 06cb,83d7; expected one exact row", result.stdout)
        self.assertIn("mode 0644, expected 0600", result.stdout)
        self.assertNotIn("private", result.stdout + result.stderr)
        self.assertEqual(before, [metadata(path) for path in paths])
        self.assertEqual(config, contents(self.legacy_config))
        self.assertEqual(mapping, contents(self.mapping))

    def test_app_modified_json_and_cleared_legacy_file_remain_untouched(self):
        config = APP_CONFIG.replace(b'"client_vsync": {"value": 0}', b'"client_vsync": {"value": 1}')
        self.assertEqual("", self.invoke().stderr)
        saved_config = self.parent / "app-save.json"
        write(saved_config, config, 0o640)
        saved_config.replace(self.config)
        write(self.legacy_config, b"")  # Parsec clears old assignments after migrating them.
        original_mapping = b"0001,0002 custom controls\n" + ROW
        self.mapping.write_bytes(original_mapping)
        paths = (self.config, self.legacy_config, self.mapping)
        before = [metadata(path) for path in paths]
        for _ in range(2):
            activation = self.invoke()
            self.assertEqual(2, activation.stderr.count("existing entry preserved; skipped the seed"))
            self.assertIn("parsec-activation-review", activation.stderr)
            review = self.invoke(1, review=True)
            self.assertIn("config.json: client_vsync=0 [different value]", review.stdout)
            self.assertIn("config.json: mode 0640, expected 0600", review.stdout)
            self.assertIn("config.txt: no declared legacy assignments", review.stdout)
            self.assertNotIn("private JSON sentinel", review.stdout + review.stderr)
        self.assertEqual(before, [metadata(path) for path in paths])
        self.assertEqual(b"", contents(self.legacy_config))
        self.assertEqual(config, contents(self.config))
        self.assertEqual(original_mapping, contents(self.mapping))

    def test_app_config_alone_allows_only_missing_mapping_seed(self):
        self.parent.mkdir()
        write(self.config, APP_CONFIG)
        before = metadata(self.config)
        self.assertEqual(1, self.invoke().stderr.count("existing entry preserved; skipped the seed"))
        self.assertEqual({"config.json", "gpmap.txt"}, {path.name for path in self.parent.iterdir()})
        self.assertEqual(ROW, contents(self.mapping))
        review = self.invoke(review=True)
        self.assertIn("config.json: client_vsync=0 [present]", review.stdout)
        self.assertIn("config.txt: missing", review.stdout)
        self.assertEqual(before, metadata(self.config))

    def test_review_pending_legacy_import_and_malformed_json(self):
        self.parent.mkdir()
        write(self.legacy_config, LEGACY_INPUT)
        write(self.mapping, ROW)
        write(self.config, APP_CONFIG)
        review = self.invoke(1, review=True)
        self.assertIn("config.json: client_vsync=0 [present]", review.stdout)
        self.assertIn("config.txt: client_vsync=0 [different value]", review.stdout)
        self.assertIn("review possible import", review.stdout)
        malformed = b'{"client_vsync": 0, "client_vsync": 1, "private malformed sentinel": 2}'
        self.config.write_bytes(malformed)
        before = metadata(self.config)
        self.assertIn("existing entry preserved; skipped the seed", self.invoke().stderr)
        review = self.invoke(1, review=True)
        self.assertIn("config.json: Conflict: expected a valid Parsec JSON object with unique keys", review.stderr)
        self.assertNotIn("private malformed sentinel", review.stdout + review.stderr)
        self.assertEqual(before, metadata(self.config))
        self.assertEqual(malformed, contents(self.config))

    def test_existing_legacy_file_blocks_json_seed_and_keeps_user_input(self):
        self.parent.mkdir()
        write(self.legacy_config, LEGACY_INPUT, 0o640)
        before = metadata(self.legacy_config)
        for _ in range(2):
            self.assertIn("config.txt exists; skipped the native config seed", self.invoke().stderr)
            self.assertFalse(self.config.exists())
        self.assertEqual(ROW, contents(self.mapping))
        review = self.invoke(1, review=True)
        self.assertIn("config.json: missing", review.stdout)
        self.assertIn("config.txt: client_vsync=0 [different value]", review.stdout)
        self.assertNotIn("private legacy sentinel", review.stdout + review.stderr)
        self.assertEqual(before, metadata(self.legacy_config))
        self.assertEqual(LEGACY_INPUT, contents(self.legacy_config))

    def test_unsafe_legacy_entries_block_json_seed_without_following_targets(self):
        self.parent.mkdir()
        target = self.home / "unrelated"
        write(target, APP_CONFIG)
        def check_refusal():
            before = [metadata(path) for path in (target, self.legacy_config)]
            self.assertIn("config.txt exists; skipped the native config seed", self.invoke().stderr)
            self.assertFalse(self.config.exists())
            review = self.invoke(1, review=True)
            self.assertIn("config.txt: Conflict: existing entry is not a user-owned regular file", review.stderr)
            self.assertNotIn("config.txt: client_vsync", review.stdout)
            self.assertEqual(before, [metadata(path) for path in (target, self.legacy_config)])

        self.legacy_config.symlink_to(target)
        check_refusal()
        self.legacy_config.unlink()
        self.legacy_config.symlink_to("missing")
        check_refusal()
        self.legacy_config.unlink()
        os.mkfifo(self.legacy_config)
        check_refusal()
        self.legacy_config.unlink()
        self.legacy_config.mkdir()
        check_refusal()

    def test_unreadable_app_config_does_not_block_missing_mapping_seed(self):
        self.parent.mkdir()
        write(self.config, APP_CONFIG, 0)
        before = metadata(self.config)
        self.assertIn("existing entry preserved; skipped the seed", self.invoke().stderr)
        self.assertIn("config.json: IOError: errno 13", self.invoke(74, review=True).stderr)
        self.assertEqual(before, metadata(self.config))
        self.assertEqual(ROW, contents(self.mapping))
        self.config.chmod(0o600)
        self.assertEqual(APP_CONFIG, contents(self.config))

    def test_older_home_manager_store_link_is_preserved(self):
        self.parent.mkdir()
        # This fixture is supplied by Nix as a read-only store path.
        target = Path(__file__).resolve()
        self.legacy_config.symlink_to(target)
        before = metadata(self.legacy_config)
        self.assertIn("config.txt exists; skipped the native config seed", self.invoke().stderr)
        self.assertFalse(self.config.exists())
        self.assertEqual(ROW, contents(self.mapping))
        self.assertIn("config.txt: Conflict", self.invoke(1, review=True).stderr)
        self.assertEqual(before, metadata(self.legacy_config))
        self.assertEqual(target, self.legacy_config.readlink())

    def test_unsafe_parent_does_not_write_through_symlink(self):
        target = self.home / "other"
        target.mkdir()
        self.parent.symlink_to(target)
        self.assertIn("Unsupported", self.invoke().stderr)
        self.assertIn("Unsupported", self.invoke(1, review=True).stderr)
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
                self.assertEqual(2, self.invoke(1, review=True).stderr.count("not a user-owned regular file"))
                self.assertEqual(before, [metadata(path) for path in (self.config, self.mapping, self.legacy, target)])
                self.assertEqual(b"unrelated", contents(target))
                if kind == "directory":
                    self.mapping.rename(self.parent / "original-directory")
                    target = self.parent / "original-directory" / "unrelated"
                    self.mapping.symlink_to(target.parent)
                elif kind == "dir-link":
                    self.mapping.unlink()
                    os.mkfifo(self.mapping)

    def test_app_created_json_wins_at_commit(self):
        result = self.invoke(fault="config-race")
        self.assertIn("another writer created the final entry", result.stderr)
        self.assertEqual(APP_CONFIG, contents(self.config))
        self.assertEqual(0o640, stat.S_IMODE(self.config.stat().st_mode))
        self.assertEqual(ROW, contents(self.mapping))
        self.assertEqual({"config.json", "gpmap.txt"}, {path.name for path in self.parent.iterdir()})
        before = metadata(self.config)
        self.assertIn("existing entry preserved; skipped the seed", self.invoke().stderr)
        review = self.invoke(1, review=True)
        self.assertIn("config.json: mode 0640, expected 0600", review.stdout)
        self.assertEqual(before, metadata(self.config))
        self.assertEqual(APP_CONFIG, contents(self.config))

    def test_legacy_input_observed_before_link_blocks_native_seed(self):
        result = self.invoke(fault="legacy-before-link")
        self.assertIn("config.txt exists; skipped the native config seed", result.stderr)
        self.assertEqual({"config.txt", "gpmap.txt"}, {path.name for path in self.parent.iterdir()})
        self.assertEqual(LEGACY_INPUT, contents(self.legacy_config))
        self.assertEqual(ROW, contents(self.mapping))

    def test_legacy_input_created_at_link_remains_user_owned(self):
        activation = self.invoke(fault="legacy-at-link")
        self.assertIn("config.json seeded; config.txt appeared during publication", activation.stderr)
        self.assertIn("Both entries were preserved", activation.stderr)
        self.assertEqual(SEED, json.loads(contents(self.config)))
        self.assertEqual(LEGACY_INPUT, contents(self.legacy_config))
        self.assertEqual(0o640, stat.S_IMODE(self.legacy_config.stat().st_mode))
        self.assertEqual(ROW, contents(self.mapping))
        before = metadata(self.legacy_config)
        review = self.invoke(1, review=True)
        self.assertIn("review possible import", review.stdout)
        self.assertIn("config.txt: client_vsync=0 [different value]", review.stdout)
        self.assertEqual(before, metadata(self.legacy_config))

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
        self.assertEqual(SEED, json.loads(contents(self.home / "moved" / "config.json")))
        self.assertFalse((self.home / "new-parent" / "config.json").exists())

    def test_unsupported_and_failed_file_flush_do_not_publish(self):
        self.assertIn("filesystem does not support unnamed staging", self.invoke(fault="no-tmpfile").stderr)
        self.assertEqual([], list(self.parent.iterdir()))
        self.assertIn("no file published", self.invoke(74, fault="file-flush").stderr)
        self.assertEqual([], list(self.parent.iterdir()))

    def test_directory_flush_failure_reports_visible_final(self):
        self.assertIn("OutcomeUnknown: final may be visible", self.invoke(75, fault="dir-flush").stderr)
        self.assertEqual(SEED, json.loads(contents(self.config)))
        before = metadata(self.config)
        self.assertFalse(self.mapping.exists())
        self.assertIn("existing entry preserved; skipped the seed", self.invoke().stderr)
        self.assertEqual(before, metadata(self.config))
        self.assertEqual(ROW, contents(self.mapping))


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
        if fault == "config-race" and event == "os.link" and payload[1] == "config.json":
            # A different process does not cooperate with any activation check.
            subprocess.run([sys.executable, "-I", "-c", """
import os
from pathlib import Path
import sys
p = Path(os.environ['HOME']) / '.parsec' / 'config.json'
with p.open('xb') as f:
    f.write(sys.argv[1].encode())
p.chmod(0o640)
""", APP_CONFIG.decode()], check=True)
        elif fault == "no-tmpfile" and event == "open" and payload[2] & os.O_TMPFILE == os.O_TMPFILE:
            raise OSError(errno.EOPNOTSUPP, os.strerror(errno.EOPNOTSUPP))
        elif fault == "legacy-before-link" and args[-1] == "config" and event == "subprocess.Popen" and payload[1][-2] == "fsync":
            write(Path(os.environ["HOME"]) / ".parsec" / "config.txt", LEGACY_INPUT, 0o640)
        elif fault == "legacy-at-link" and event == "os.link" and payload[1] == "config.json":
            write(Path(os.environ["HOME"]) / ".parsec" / "config.txt", LEGACY_INPUT, 0o640)
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
        REVIEW = sys.argv.pop(1)
        unittest.main(verbosity=2)
