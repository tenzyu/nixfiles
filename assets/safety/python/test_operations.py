"""Isolated ADR-0002 fixtures for the packaged safety_operations module."""

from dataclasses import FrozenInstanceError, replace
import errno
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import safety_operations as safety


def snapshot(path):
    info = path.lstat()
    if path.is_symlink():
        contents = os.readlink(path)
    elif path.is_dir():
        contents = sorted((entry.name, snapshot(entry)) for entry in path.iterdir())
    else:
        contents = path.read_bytes()
    return info.st_dev, info.st_ino, info.st_mode, contents


class OperationsTests(unittest.TestCase):
    def setUp(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.source_dir = root / "source"
        self.target_dir = root / "target"
        self.source_dir.mkdir(mode=0o700)
        self.target_dir.mkdir(mode=0o700)
        self.source_fd = self.open_parent(self.source_dir)
        self.target_fd = self.open_parent(self.target_dir)
        self.source = self.source_dir / "old"
        self.target = self.target_dir / "new"

    def open_parent(self, path, flags=os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW):
        fd = os.open(path, flags)
        self.addCleanup(os.close, fd)
        return fd

    def intent(self, source_type=stat.S_IFREG):
        return safety.MoveNew(
            os.geteuid(),
            safety.Leaf(self.source_fd, self.source.name),
            safety.Leaf(self.target_fd, self.target.name),
            source_type,
        )

    def test_intent_01_construction_and_denial_are_read_only(self):
        self.source.write_bytes(b"data")
        before = snapshot(self.source_dir)
        intent = self.intent()
        with self.assertRaises(FrozenInstanceError):
            intent.target = intent.source
        with self.assertRaises(FrozenInstanceError):
            intent.target.name = "substitute"
        with self.assertRaises(safety.Denied):
            safety.execute_move(intent)
        with self.assertRaises(safety.Denied):
            safety.execute_move(intent, confirmed=1)
        with self.assertRaises(safety.Denied):
            safety.execute_move(replace(intent, actor_uid=intent.actor_uid + 1), confirmed=True)
        with self.assertRaises(safety.Denied):
            safety.execute_move({"operation": "unknown"}, confirmed=True)
        with self.assertRaises(safety.Denied):
            replace(intent, target=intent.source)
        with self.assertRaises(safety.Denied):
            replace(intent, source_type=stat.S_IFLNK)
        self.assertEqual(snapshot(self.source_dir), before)
        self.assertEqual(list(self.target_dir.iterdir()), [])

    def test_boundary_01_invalid_leaf_names_and_parent_descriptors(self):
        for name in ("", ".", "..", "../escape", "/absolute", "parent/leaf", "null\0byte"):
            with self.subTest(name=name), self.assertRaises(safety.Denied):
                safety.Leaf(self.target_fd, name)
        self.source.write_bytes(b"data")
        link = self.source_dir / "alias"
        link.symlink_to(self.target_dir)
        for path in (self.source, link):
            with self.subTest(path=path.name), self.assertRaises(safety.Denied):
                safety.Leaf(self.open_parent(path, os.O_PATH | os.O_NOFOLLOW), "leaf")
        with self.assertRaises(safety.Unsupported):
            safety.Leaf(self.open_parent(self.target_dir, os.O_PATH), "leaf")
        self.assertEqual(list(self.target_dir.iterdir()), [])

    def test_boundary_01_changed_source_type_denies_move(self):
        self.source.symlink_to("missing")
        before = snapshot(self.source)
        with self.assertRaises(safety.Denied):
            safety.execute_move(self.intent(), confirmed=True)
        self.assertEqual(snapshot(self.source), before)
        self.assertFalse(os.path.lexists(self.target))

    def test_boundary_01_descriptor_rebound_to_another_directory_is_denied(self):
        self.source.write_bytes(b"data")
        intent = self.intent()
        os.dup2(self.source_fd, self.target_fd)
        with self.assertRaises(safety.Denied):
            safety.execute_move(intent, confirmed=True)
        self.assertEqual(self.source.read_bytes(), b"data")
        self.assertFalse(os.path.lexists(self.source_dir / self.target.name))
        self.assertEqual(list(self.target_dir.iterdir()), [])

    def test_boundary_01_parent_move_keeps_the_selected_directory(self):
        self.source.write_bytes(b"data")
        intent = self.intent()
        moved = self.target_dir.rename(self.target_dir.with_name("moved"))
        self.target_dir.mkdir()
        self.target.write_bytes(b"replacement parent")
        replacement = snapshot(self.target)
        safety.execute_move(intent, confirmed=True)
        self.assertEqual((moved / self.target.name).read_bytes(), b"data")
        self.assertEqual(snapshot(self.target), replacement)
        self.assertEqual(list(self.source_dir.iterdir()), [])

    def test_boundary_01_cross_filesystem_move_has_no_fallback(self):
        shared_memory = Path("/dev/shm")
        if not shared_memory.is_dir() or not os.access(shared_memory, os.W_OK):
            self.skipTest("no writable /dev/shm for a second filesystem")
        if shared_memory.stat().st_dev == self.source_dir.stat().st_dev:
            self.skipTest("/dev/shm is on the fixture's filesystem")
        other = Path(self.enterContext(tempfile.TemporaryDirectory(dir=shared_memory)))
        self.source.write_bytes(b"data")
        source = snapshot(self.source)
        target = safety.Leaf(self.open_parent(other), self.target.name)
        with self.assertRaises(safety.Unsupported) as caught:
            safety.execute_move(replace(self.intent(), target=target), confirmed=True)
        self.assertEqual(caught.exception.errno, errno.EXDEV)
        self.assertEqual(snapshot(self.source), source)
        self.assertEqual(list(other.iterdir()), [])

    def test_publish_01_directory_move_preserves_inode_and_children(self):
        self.source.mkdir(mode=0o750)
        (self.source / "data").write_bytes(b"saved directory contents")
        original = snapshot(self.source)
        safety.execute_move(self.intent(stat.S_IFDIR), confirmed=True)
        self.assertEqual(snapshot(self.target), original)
        self.assertEqual(list(self.source_dir.iterdir()), [])

    def test_publish_01_validated_private_file_stage(self):
        # The adapter owns and flushes this regular stage before dispatch.
        fd = os.open(self.source.name, os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600,
                     dir_fd=self.source_fd)
        with os.fdopen(fd, "w+b") as stage:
            stage.write(b"validated backup")
            stage.seek(0)
            self.assertEqual(stage.read(), b"validated backup")
            os.fsync(stage.fileno())
            original = snapshot(self.source)
            safety.execute_move(self.intent(), confirmed=True)
            self.assertEqual(self.target.stat().st_ino, os.fstat(stage.fileno()).st_ino)
        self.assertEqual(snapshot(self.target), original)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        self.assertEqual(list(self.target_dir.iterdir()), [self.target])
        self.assertEqual(list(self.source_dir.iterdir()), [])

    def test_publish_01_all_existing_leaf_types_conflict(self):
        self.source.write_bytes(b"pending")
        source = snapshot(self.source)
        referent = self.target_dir / "referent"
        referent.mkdir()
        (referent / "entry").write_bytes(b"keep")
        cases = {
            "file": lambda: self.target.write_bytes(b"existing"),
            "empty-directory": self.target.mkdir,
            "dangling-link": lambda: self.target.symlink_to("missing"),
            "directory-link": lambda: self.target.symlink_to(referent.name),
        }
        for label, setup in cases.items():
            with self.subTest(label=label):
                setup()
                before = snapshot(self.target_dir)
                with self.assertRaises(safety.Conflict) as caught:
                    safety.execute_move(self.intent(), confirmed=True)
                self.assertEqual(caught.exception.errno, errno.EEXIST)
                self.assertEqual(snapshot(self.target_dir), before)
                self.assertEqual(snapshot(self.source), source)
                if self.target.is_symlink() or not self.target.is_dir():
                    self.target.unlink()
                else:
                    self.target.rmdir()

    def test_publish_01_shell_and_python_contend_for_the_same_final(self):
        self.source.write_bytes(b"Python payload")
        shell_stage = self.target_dir / "shell-stage"
        shell_stage.write_bytes(b"Shell payload")
        shell_original = snapshot(shell_stage)
        python_original = snapshot(self.source)
        command = [
            os.environ.get("SAFETY_TEST_BASH", "bash"), "-c",
            'IFS= read -r ready || exit; exec "$@"', "bash",
            os.environ.get("SAFETY_TEST_LN", "ln"), "-T", "--", shell_stage, self.target,
        ]
        with subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, env={**os.environ, "LC_ALL": "C"}) as child:
            child.stdin.write("\n")
            child.stdin.flush()
            try:
                safety.execute_move(self.intent(), confirmed=True)
            except safety.Conflict:
                python_won = False
            else:
                python_won = True
            _, diagnostic = child.communicate(timeout=10)

        self.assertEqual(snapshot(shell_stage), shell_original)
        if python_won:
            self.assertEqual(child.returncode, 1, diagnostic)
            self.assertIn("File exists", diagnostic)
            self.assertEqual(snapshot(self.target), python_original)
            self.assertFalse(os.path.lexists(self.source))
        else:
            self.assertEqual(child.returncode, 0, diagnostic)
            self.assertEqual(snapshot(self.target), shell_original)
            self.assertEqual(snapshot(self.source), python_original)

    def test_publish_02_precommit_failures_preserve_errno_and_entries(self):
        self.source.write_bytes(b"pending")
        source = snapshot(self.source)
        for code, failure in ((errno.ENOSYS, safety.Unsupported), (errno.ENOSPC, OSError),
                              (errno.EINTR, safety.OutcomeUnknown)):
            with self.subTest(code=code):
                injected = OSError(code, os.strerror(code))
                with (patch.object(safety, "_rename_noreplace", side_effect=injected),
                      patch.object(os, "fsync") as fsync, self.assertRaises(failure) as caught):
                    safety.execute_move(self.intent(), confirmed=True)
                self.assertIs(type(caught.exception), failure)
                self.assertEqual(caught.exception.errno, code)
                self.assertIs(caught.exception.__cause__ or caught.exception, injected)
                fsync.assert_not_called()
                self.assertEqual(snapshot(self.source), source)
                self.assertEqual(list(self.target_dir.iterdir()), [])

    def test_publish_02_flushes_target_then_source_after_rename(self):
        self.source.write_bytes(b"pending")
        fsync = os.fsync
        synced = []

        def observe(fd):
            self.assertEqual(self.target.read_bytes(), b"pending")
            self.assertFalse(os.path.lexists(self.source))
            synced.append(fd)
            fsync(fd)

        with patch.object(os, "fsync", side_effect=observe):
            safety.execute_move(self.intent(), confirmed=True)
        self.assertEqual(synced, [self.target_fd, self.source_fd])

    def test_publish_02_interrupt_at_rename_can_leave_a_visible_final(self):
        self.source.write_bytes(b"pending")
        original = snapshot(self.source)
        rename = safety._rename_noreplace

        def publish_and_interrupt(source, target):
            rename(source, target)
            raise KeyboardInterrupt

        with (patch.object(safety, "_rename_noreplace", side_effect=publish_and_interrupt),
              self.assertRaises(safety.OutcomeUnknown) as caught):
            safety.execute_move(self.intent(), confirmed=True)
        self.assertIsInstance(caught.exception.__cause__, KeyboardInterrupt)
        self.assertEqual(snapshot(self.target), original)
        self.assertFalse(os.path.lexists(self.source))

    def test_recovery_01_failed_parent_flush_keeps_published_final(self):
        unrelated = self.source_dir / "abandoned"
        unrelated.write_bytes(b"unrelated leftover")
        untouched = snapshot(unrelated)
        for failed_fd in (self.target_fd, self.source_fd):
            with self.subTest(failed_fd=failed_fd):
                self.source.write_bytes(b"pending")
                original = snapshot(self.source)
                injected = OSError(errno.EIO, "simulated parent flush failure")
                fsync = os.fsync

                def flush(fd):
                    if fd == failed_fd:
                        raise injected
                    fsync(fd)

                with patch.object(os, "fsync", side_effect=flush):
                    with self.assertRaises(safety.OutcomeUnknown) as caught:
                        safety.execute_move(self.intent(), confirmed=True)
                self.assertIs(caught.exception.__cause__, injected)
                self.assertEqual(caught.exception.errno, errno.EIO)
                self.assertEqual(snapshot(self.target), original)
                self.assertFalse(os.path.lexists(self.source))
                self.source.write_bytes(b"another attempt")
                with self.assertRaises(safety.Conflict):
                    safety.execute_move(self.intent(), confirmed=True)
                self.assertEqual(snapshot(self.target), original)
                self.assertEqual(self.source.read_bytes(), b"another attempt")
                self.assertEqual(snapshot(unrelated), untouched)
                # Reset only the isolated fixture before exercising the other fd.
                self.target.unlink()


if __name__ == "__main__":
    unittest.main()
