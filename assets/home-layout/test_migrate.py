"""Data-preservation regression tests; fixtures never touch the real home."""

from contextlib import redirect_stdout, redirect_stderr
import errno
import fcntl
import io
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import migrate


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.enterContext(patch.dict(os.environ, {"HOME": str(self.home)}))
        root = Path("/").stat()
        build_dir = os.environ.get("NIX_BUILD_TOP")
        self.sandbox_root = build_dir and root.st_uid not in (0, os.geteuid())
        if self.sandbox_root:
            # Nix maps only the build user. The outer UID of the sandbox's
            # synthetic root is unmapped. Keep the production ancestry check
            # and simulate its root-owner check only within the fixture process.
            self.assertTrue(self.home.is_relative_to(Path(build_dir)))
            self.assertEqual(root.st_mode & 0o022, 0)
            trust = migrate.MoveBoundary.trust

            def trust_sandbox_root(boundary, fd, path, **options):
                if path == Path("/"):
                    return False
                return trust(boundary, fd, path, **options)

            self.enterContext(patch.object(migrate.MoveBoundary, "trust", trust_sandbox_root))
        if build_dir:
            mount_table = migrate.MoveBoundary.mount_table

            def fixture_mount_table():
                return {number: (device, Path("/") if path == Path(build_dir) else root, path, filesystem)
                        for number, (device, root, path, filesystem) in mount_table().items()}

            self.enterContext(patch.object(migrate.MoveBoundary, "mount_table", staticmethod(fixture_mount_table)))
        self.sandbox_xattr_listing = False
        if build_dir:
            try:
                os.listxattr(self.home)
            except OSError as error:
                if error.errno != errno.ENOTSUP:
                    raise
                # Some Nix sandbox tmpfs builds cannot even enumerate xattrs.
                # Model an empty attribute list for the ordinary fixtures. A
                # separate test below injects ENOTSUP on the production path.
                self.sandbox_xattr_listing = True
                self.enterContext(patch.object(migrate.os, "listxattr", return_value=[]))
        self.manifest = {"home": str(self.home), "state": str(self.home / "state"),
                         "rules": [], "managed": []}

    def file(self, relative, content="credentials", mode=0o600):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(mode)
        return path

    def rule(self, source, target, **extra):
        rule = {"owner": "fixture", "source": str(self.home / source),
                "target": str(self.home / target), **extra}
        self.manifest["rules"].append(rule)
        return rule

    def journal(self):
        journal, = (self.home / "state").glob("*/operations.jsonl")
        return [json.loads(line) for line in journal.read_text().splitlines()]

    def recover(self, group="fixture"):
        run = self.journal()[0]["run"]
        migrate.mutate(self.manifest, "recover", group, {}, shutil.which("rsync"), run_id=run)

    def test_fresh_home_and_repeat_are_noops(self):
        self.rule(".old", ".local/share/new")
        self.assertEqual(migrate.plan(self.manifest), [])
        self.assertEqual(migrate.apply(self.manifest), [])
        self.assertFalse((self.home / "state").exists())

    def test_move_preserves_credentials_inode_mode_and_relative_links(self):
        source = self.file(".old/key")
        before = source.stat()
        (source.parent / "alias").symlink_to("key")
        self.rule(".old", ".local/share/new")
        migrate.apply(self.manifest)
        target = self.home / ".local/share/new/key"
        self.assertEqual(target.read_text(), "credentials")
        self.assertEqual(target.stat().st_ino, before.st_ino)
        self.assertEqual(target.stat().st_mode, before.st_mode)
        self.assertEqual((target.parent / "alias").read_text(), "credentials")
        self.assertEqual(migrate.apply(self.manifest), [])

    def test_all_conflicts_checked_before_any_move(self):
        self.file(".first/key")
        self.file(".second/key", "old")
        self.file("new-second/key", "new")
        self.rule(".first", "new-first")
        self.rule(".second", "new-second")
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)
        self.assertTrue((self.home / ".first/key").exists())
        self.assertEqual((self.home / "new-second/key").read_text(), "new")
        self.assertFalse((self.home / "state").exists())

    def test_claude_nested_json_and_collision(self):
        self.file(".claude/settings.json", "{}")
        self.file(".claude.json", '{"auth": "keep"}')
        self.rule(".claude", ".config/claude")
        self.rule(".claude.json", ".config/claude/.claude.json")
        hidden = self.file(".claude/.claude.json", '{"auth": "other"}')
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)
        hidden.unlink()
        migrate.apply(self.manifest)
        self.assertEqual(json.loads((self.home / ".config/claude/.claude.json").read_text()),
                         {"auth": "keep"})

    def test_bun_split_cache_then_installation(self):
        cache = self.file(".bun/install/cache/package", "cache")
        binary = self.file(".bun/bin/bun", "binary", 0o755)
        inodes = cache.stat().st_ino, binary.stat().st_ino
        self.rule(".bun/install/cache", ".cache/bun/install")
        self.rule(".bun", ".local/share/bun")
        migrate.apply(self.manifest)
        self.assertEqual((self.home / ".cache/bun/install/package").stat().st_ino, inodes[0])
        self.assertEqual((self.home / ".local/share/bun/bin/bun").stat().st_ino, inodes[1])

    def test_firefox_generated_scaffolding_is_saved_not_merged(self):
        self.file(".mozilla/firefox/default/places.sqlite", "bookmarks")
        scaffolding = self.home / ".config/mozilla/firefox/default/user.js"
        scaffolding.parent.mkdir(parents=True)
        scaffolding.symlink_to("/nix/store/nonexistent-home-manager-files/user.js")
        self.rule(".mozilla/firefox", ".config/mozilla/firefox")
        self.manifest["managed"] = [str(scaffolding)]
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)  # A matching store-name shape is insufficient.
        migrate.apply(self.manifest, generated={scaffolding: {str(scaffolding.readlink())}})
        self.assertEqual((scaffolding.parent / "places.sqlite").read_text(), "bookmarks")
        saved = list((self.home / ".config/mozilla").glob(".home-layout-*-scaffold-0/payload/default/user.js"))
        self.assertEqual(len(saved), 1)
        self.assertTrue(saved[0].is_symlink())

    def test_firefox_existing_real_destination_blocks(self):
        self.file(".mozilla/firefox/default/key4.db")
        self.file(".config/mozilla/firefox/default/places.sqlite")
        self.rule(".mozilla/firefox", ".config/mozilla/firefox")
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)

    def test_future_managed_file_collision_blocks(self):
        self.file(".mozilla/firefox/profiles.ini", "user profile selection")
        self.rule(".mozilla/firefox", ".config/mozilla/firefox")
        self.manifest["managed"] = [str(self.home / ".config/mozilla/firefox/profiles.ini")]
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)

    def test_symlink_sources_destinations_and_changed_meaning_block(self):
        self.file("elsewhere/key")
        (self.home / ".old").symlink_to("elsewhere", target_is_directory=True)
        self.rule(".old", "new")
        with self.assertRaises(migrate.Conflict):
            migrate.plan(self.manifest)
        (self.home / ".old").unlink()
        self.file(".old/key")
        (self.home / "new").symlink_to("absent")
        with self.assertRaises(migrate.Conflict):
            migrate.plan(self.manifest)
        (self.home / "new").unlink()
        (self.home / ".old/link").symlink_to("../elsewhere/key")
        self.manifest["rules"][0]["target"] = str(self.home / ".local/share/new")
        with self.assertRaises(migrate.Conflict):
            migrate.plan(self.manifest)

    def test_check_is_read_only_and_busy_application_blocks(self):
        self.file(".android/adbkey")
        self.rule(".android", ".local/share/android/.android", processes=["adb", ".adb-wrapped"])
        with patch.object(migrate, "busy", return_value=["123"]):
            with self.assertRaises(migrate.Conflict):
                migrate.apply(self.manifest)
        with patch.object(migrate, "busy", return_value=[]):
            self.assertEqual(len(migrate.plan(self.manifest)), 1)
        self.assertTrue((self.home / ".android/adbkey").exists())
        self.assertFalse((self.home / "state").exists())

    def test_container_node_blocks_only_when_home_filesystem_is_exposed(self):
        proc = self.home / "proc" / "123"
        proc.mkdir(parents=True)
        (proc / "comm").write_text("node\n")
        (proc / "cmdline").write_bytes(b"node\0opt/index.js\0")
        (proc / "exe").symlink_to("/container/bin/node")
        device = self.home.stat().st_dev
        device_id = f"{os.major(device)}:{os.minor(device)}"
        mounts = migrate.mounts

        def mount_table(path):
            if path == Path("/proc/self/mountinfo"):
                return iter([(device_id, Path("/"), Path("/"))])
            return mounts(path)

        self.enterContext(patch.object(migrate, "mounts", side_effect=mount_table))
        cases = [
            ("1 0 0:999 / / rw - overlay overlay rw\n", []),
            (f"1 0 {device_id} {self.home}/.local/share/docker/hostname /etc/hostname rw - ext4 disk rw\n", []),
            # A bind mount at another container path still exposes the home.
            (f"1 0 {device_id} {self.home} /data rw - ext4 disk rw\n", ["123"]),
            (f"1 0 {device_id} / / rw - ext4 disk rw\n", ["123"]),
        ]
        for mountinfo, expected in cases:
            with self.subTest(mountinfo=mountinfo):
                (proc / "mountinfo").write_text(mountinfo)
                with patch.object(Path, "iterdir", return_value=iter([proc])):
                    self.assertEqual(migrate.busy(["node"], [self.home / ".npm"]), expected)
        (proc / "mountinfo").unlink()
        with patch.object(Path, "iterdir", return_value=iter([proc])):
            self.assertEqual(migrate.busy(["node"], [self.home / ".npm"]), ["123"])

    def test_reference_repair_after_directory_move_requires_operator_review(self):
        # A prior version moved the directory but left an old reference behind.
        old = self.home / ".codex"
        original = json.dumps({"command": f"{old}/hook.sh", "other": f"{old}-other/keep"})
        reference = self.file(".local/share/codex/hooks.json", original)
        before = reference.stat()
        self.rule(".codex", ".local/share/codex", references=["hooks.json"])
        action, = migrate.plan(self.manifest)
        self.assertEqual(action["action"], "rewrite")
        self.assertEqual(action["current"], str(reference))
        updated = migrate.replace_references(original, old, reference.parent, self.home)
        self.assertEqual(json.loads(updated), {"command": str(reference.parent / "hook.sh"),
                                               "other": f"{old}-other/keep"})
        with self.assertRaisesRegex(migrate.Unsupported, "exclusive ownership"):
            migrate.apply(self.manifest)
        self.assertEqual(reference.read_text(), original)
        self.assertEqual(reference.stat().st_ino, before.st_ino)
        self.assertEqual(reference.stat().st_mode, before.st_mode)
        self.assertFalse((self.home / "state").exists())
        reference.write_text(updated)  # Separate operator remediation in this fixture.
        self.assertEqual(migrate.apply(self.manifest), [])

    def test_late_empty_directory_is_never_backed_up_or_overwritten(self):
        source = self.file(".old/key")
        self.rule(".old", "target", onConflict="backup")
        target = self.home / "target"
        execute = migrate.safety.execute_move

        def compete(intent, **kwargs):
            target.mkdir(mode=0o750)
            self.late_inode = target.stat().st_ino
            return execute(intent, **kwargs)

        with patch.object(migrate.safety, "execute_move", side_effect=compete):
            with self.assertRaises(migrate.safety.Conflict):
                migrate.apply(self.manifest)
        self.assertEqual(source.read_text(), "credentials")
        self.assertEqual(target.stat().st_ino, self.late_inode)
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual([e["event"] for e in self.journal()], ["begin", "intent"])

    def cross_mount(self):
        def unavailable(reason):
            if os.environ.get("NIXFILES_REQUIRE_CROSS_MOUNT"):
                self.fail(reason)
            self.skipTest(reason)

        if os.environ.get("NIX_BUILD_TOP"):
            unavailable("cross-mount coverage runs on the disposable VM's two real filesystems")
        mount = Path(os.environ.get("NIXFILES_CROSS_MOUNT", "/dev/shm"))
        if not shutil.which("rsync"):
            unavailable("real cross-mount fixture could not find rsync on PATH")
        if not mount.is_dir():
            unavailable(f"real cross-mount fixture mount is missing: {mount}")
        if not os.access(mount, os.W_OK | os.X_OK):
            unavailable(f"real cross-mount fixture mount is not writable by the fixture UID: {mount}")
        try:
            destination = self.enterContext(tempfile.TemporaryDirectory(dir=mount))
        except OSError as error:
            unavailable(f"real cross-mount fixture unavailable: {error}")
        target = Path(destination) / "new"
        if self.home.stat().st_dev == target.parent.stat().st_dev:
            unavailable("fixture requires two distinct filesystems")
        self.manifest.update(version=2, externalBases=[destination])
        self.rule(".old", ".unused")["target"] = str(target)
        return target

    def test_cross_mount_copy_and_separately_reversible_retirement(self):
        target = self.cross_mount()
        original = self.file(".old/key", "legacy-record")
        os.link(original, original.with_name("hardlink"))
        original.with_name("alias").symlink_to("key")
        sparse = original.with_name("sparse")
        with sparse.open("wb") as stream:
            stream.seek(1024 * 1024)
            stream.write(b"end")
        if shutil.which("setfacl"):
            subprocess.run(["setfacl", "-m", "u:65534:r--", original], check=True)
        os.setxattr(original, "user.fixture", b"metadata")
        inode = original.stat().st_ino
        actions = migrate.apply(self.manifest, rsync=shutil.which("rsync"))
        self.assertEqual(actions[0]["action"], "move")
        first = self.journal()[0]["run"]
        self.assertEqual(migrate.apply(self.manifest, rsync=shutil.which("rsync")), [])
        self.assertEqual(original.stat().st_ino, inode)
        self.assertEqual((target / "alias").read_text(), "legacy-record")
        self.assertEqual((target / "key").stat().st_ino, (target / "hardlink").stat().st_ino)
        self.assertEqual(os.getxattr(target / "key", "user.fixture"), b"metadata")
        self.assertLess((target / "sparse").stat().st_blocks * 512, sparse.stat().st_size)
        if shutil.which("getfacl"):
            self.assertEqual(subprocess.check_output(["getfacl", "-cp", original]),
                             subprocess.check_output(["getfacl", "-cp", target / "key"]))
        migrate.mutate(self.manifest, "retire", "fixture", {}, None, run_id=first)
        self.assertFalse(original.exists())
        retired = migrate.disposition(migrate.read_runs(migrate.MoveBoundary(), self.home / "state"),
                                       {"header": {"run": first}}, "retire")
        migrate.mutate(self.manifest, "rollback", "fixture", {}, None, run_id=retired["header"]["run"])
        self.assertEqual(original.stat().st_ino, inode)
        migrate.mutate(self.manifest, "rollback", "fixture", {}, None, run_id=first)
        self.assertFalse(target.exists())
        self.assertEqual(original.read_text(), "legacy-record")
        self.assertEqual(len(list(target.parent.glob(".home-layout-*-rollback-*"))), 1)

    def test_cross_mount_interrupted_copy_retries_in_fresh_stage(self):
        target = self.cross_mount()
        original = self.file(".old/key", "legacy")
        rsync = migrate.subprocess.run

        def interrupt(args, **kwargs):
            Path(args[-1]).mkdir()
            Path(args[-1], "partial").write_text("incomplete")
            raise OSError("interrupted staging")
        with patch.object(migrate.subprocess, "run", side_effect=interrupt):
            with self.assertRaisesRegex(OSError, "interrupted staging"):
                migrate.apply(self.manifest, rsync=shutil.which("rsync"))
        self.assertFalse(target.exists())
        self.assertEqual(original.read_text(), "legacy")
        self.assertEqual(self.invoke("apply", "--group", "fixture", "--offline").returncode, 1)
        self.assertIs(migrate.subprocess.run, rsync)
        run = self.journal()[0]["run"]
        result = self.invoke("recover", "--group", "fixture", "--offline", "--run", run)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / "key").read_text(), "legacy")
        self.assertEqual(len(list(target.parent.glob(".home-layout-*-stage/payload/partial"))), 1)

    def test_cross_mount_external_hardlink_fails_preflight(self):
        target = self.cross_mount()
        original = self.file(".old/key")
        os.link(original, self.home / "external-link")
        with self.assertRaisesRegex(migrate.Unsupported, "hard links outside"):
            migrate.apply(self.manifest, rsync=shutil.which("rsync"))
        self.assertFalse(target.exists())
        self.assertFalse((self.home / "state").exists())

    def test_cross_mount_retirement_recovery_rechecks_published_target(self):
        target = self.cross_mount()
        first_source = self.file(".first-old/key", "other payload")
        first_target = target.with_name("first-published")
        first_rule = self.rule(".first-old", ".unused")
        first_rule["target"] = str(first_target)
        self.manifest["rules"].insert(0, self.manifest["rules"].pop())
        original = self.file(".old/key", "initial payload")
        inode = original.stat().st_ino
        migrate.apply(self.manifest, rsync=shutil.which("rsync"))
        transfer = self.journal()[0]["run"]

        with (patch.object(migrate, "execute_run", side_effect=OSError("after durable retirement header")),
              self.assertRaisesRegex(OSError, "after durable retirement header")):
            migrate.mutate(self.manifest, "retire", "fixture", {}, None, run_id=transfer)
        runs = migrate.read_runs(migrate.MoveBoundary(), self.home / "state")
        pending, = [run for run in runs if not run["finished"]]
        header = pending["header"]
        self.assertEqual(header["mode"], "retire")
        self.assertEqual(pending["events"], [])
        journal = pending["path"] / "operations.jsonl"
        before = journal.read_bytes()
        published = target / "key"
        published_info = published.stat()
        published.write_text("changed payload")
        os.utime(published, ns=(published_info.st_atime_ns, published_info.st_mtime_ns))

        recovered = self.launch("recover", "--group", "fixture", "--offline", "--run", header["run"])
        self.assertEqual(recovered.returncode, 1, recovered.stderr)
        self.assertIn("Authoritative target has changed", recovered.stderr)
        self.assertEqual(published.read_text(), "changed payload")
        self.assertEqual(original.read_text(), "initial payload")
        self.assertEqual(original.stat().st_ino, inode)
        self.assertEqual(first_source.read_text(), "other payload")
        self.assertEqual((first_target / "key").read_text(), "other payload")
        self.assertTrue(all(not Path(op["target"]).exists() for op in header["operations"]))
        self.assertEqual(journal.read_bytes(), before)

        published.write_text("initial payload")
        os.utime(published, ns=(published_info.st_atime_ns, published_info.st_mtime_ns))
        recovered = self.launch("recover", "--group", "fixture", "--offline", "--run", header["run"])
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assertFalse(first_source.exists())
        self.assertFalse(original.exists())
        self.assertEqual((Path(header["operations"][1]["target"]) / "key").read_text(), "initial payload")

    def test_cross_mount_retirement_rechecks_published_target_after_intent(self):
        target = self.cross_mount()
        original = self.file(".old/key", "initial payload")
        migrate.apply(self.manifest, rsync=shutil.which("rsync"))
        transfer = self.journal()[0]["run"]
        write = migrate.write_journal

        def change_target(log, event):
            write(log, event)
            if event["event"] == "intent":
                (target / "key").write_text("later payload")

        with (patch.object(migrate, "write_journal", side_effect=change_target),
              self.assertRaisesRegex(migrate.Conflict, "Authoritative target has changed")):
            migrate.mutate(self.manifest, "retire", "fixture", {}, None, run_id=transfer)
        self.assertEqual(original.read_text(), "initial payload")
        self.assertEqual((target / "key").read_text(), "later payload")

    def test_cross_mount_retirement_recovery_preflights_all_pending_sources(self):
        target = self.cross_mount()
        first = self.file(".old/key", "first payload")
        middle = self.file(".middle-old/key", "middle payload")
        later = self.file(".later-old/key", "original later")
        for group_member in ("middle", "later"):
            rule = self.rule(f".{group_member}-old", ".unused")
            rule["target"] = str(target.with_name(group_member))
        migrate.apply(self.manifest, rsync=shutil.which("rsync"))
        transfer = self.journal()[0]["run"]
        write = migrate.write_journal

        def stop_after_first_retirement(log, event):
            write(log, event)
            if event["event"] == "done" and event["index"] == 0:
                raise OSError("after first retirement")

        with (patch.object(migrate, "write_journal", side_effect=stop_after_first_retirement),
              self.assertRaisesRegex(OSError, "after first retirement")):
            migrate.mutate(self.manifest, "retire", "fixture", {}, None, run_id=transfer)
        runs = migrate.read_runs(migrate.MoveBoundary(), self.home / "state")
        pending, = [run for run in runs if not run["finished"]]
        header = pending["header"]
        archives = [Path(op["target"]) for op in header["operations"]]
        journal = pending["path"] / "operations.jsonl"
        before = journal.read_bytes()
        self.assertEqual([event["event"] for event in pending["events"]], ["intent", "done"])
        self.assertFalse(first.exists())
        self.assertEqual((archives[0] / "key").read_text(), "first payload")
        middle_inode = middle.stat().st_ino
        later_info = later.stat()
        later.write_text("modified later")
        os.utime(later, ns=(later_info.st_atime_ns, later_info.st_mtime_ns))
        recovery = ("recover", "--group", "fixture", "--offline", "--run", header["run"])

        refused = self.launch(*recovery)
        self.assertEqual(refused.returncode, 1, refused.stderr)
        self.assertIn("Payload changed after planning", refused.stderr)
        self.assertTrue(middle.exists(), "Recovery moved another legacy source before refusing")
        self.assertEqual(middle.read_text(), "middle payload")
        self.assertEqual(middle.stat().st_ino, middle_inode)
        self.assertEqual(later.read_text(), "modified later")
        self.assertEqual((target.with_name("later") / "key").read_text(), "original later")
        self.assertFalse(archives[1].exists())
        self.assertFalse(archives[2].exists())
        self.assertEqual(journal.read_bytes(), before)

        later.write_text("original later")
        os.utime(later, ns=(later_info.st_atime_ns, later_info.st_mtime_ns))
        archives[2].mkdir(parents=True)
        (archives[2] / "collision").write_text("leave untouched")
        refused = self.launch(*recovery)
        self.assertEqual(refused.returncode, 1, refused.stderr)
        self.assertIn("Cannot reconcile existing destination", refused.stderr)
        self.assertEqual(middle.stat().st_ino, middle_inode)
        self.assertEqual(later.read_text(), "original later")
        self.assertFalse(archives[1].exists())
        self.assertEqual((archives[2] / "collision").read_text(), "leave untouched")
        self.assertEqual(journal.read_bytes(), before)

        archives[2].rename(self.home / "preserved-collision")
        resumed = self.launch(*recovery)
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertFalse(middle.exists())
        self.assertFalse(later.exists())
        self.assertEqual([(archive / "key").read_text() for archive in archives],
                         ["first payload", "middle payload", "original later"])
        self.assertIn('"event": "finished"', journal.read_text())

    def test_cross_mount_retirement_recovery_accepts_unlogged_quarantine(self):
        target = self.cross_mount()
        source = self.file(".old/key", "original payload")
        inode = source.stat().st_ino
        migrate.apply(self.manifest, rsync=shutil.which("rsync"))
        transfer = self.journal()[0]["run"]
        write = migrate.write_journal

        def stop_before_completion(log, event):
            if event["event"] == "done":
                raise OSError("after retirement rename")
            write(log, event)

        with (patch.object(migrate, "write_journal", side_effect=stop_before_completion),
              self.assertRaisesRegex(OSError, "after retirement rename")):
            migrate.mutate(self.manifest, "retire", "fixture", {}, None, run_id=transfer)
        runs = migrate.read_runs(migrate.MoveBoundary(), self.home / "state")
        pending, = [run for run in runs if not run["finished"]]
        header = pending["header"]
        archive = Path(header["operations"][0]["target"]) / "key"
        self.assertEqual([event["event"] for event in pending["events"]], ["intent"])
        self.assertFalse(source.exists())
        self.assertEqual(archive.stat().st_ino, inode)

        resumed = self.launch("recover", "--group", "fixture", "--offline", "--run", header["run"])
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertFalse(source.exists())
        self.assertEqual(archive.stat().st_ino, inode)
        self.assertEqual((target / "key").read_text(), "original payload")
        runs = migrate.read_runs(migrate.MoveBoundary(), self.home / "state")
        self.assertTrue(all(run["finished"] for run in runs))

    def test_equal_copies_require_separate_plan_and_can_be_restored(self):
        old = self.file(".old", "authoritative bytes")
        new = self.file(".new", "authoritative bytes")
        for path in (old, new):
            os.utime(path, (100, 100))
        self.rule(".old", ".new")
        self.assertEqual(self.invoke("apply", "--group", "fixture", "--offline").returncode, 1)
        plan = self.invoke("plan", "--group", "fixture", "--retire-equal")
        self.assertEqual(plan.returncode, 0, plan.stderr)
        token = json.loads(plan.stdout)["expect"]
        retired = self.invoke("retire-equal", "--group", "fixture", "--offline", "--expect", token)
        self.assertEqual(retired.returncode, 0, retired.stderr)
        self.assertFalse(old.exists())
        self.assertEqual(new.read_text(), "authoritative bytes")
        run = self.journal()[0]["run"]
        restored = self.invoke("rollback", "--group", "fixture", "--offline", "--run", run)
        self.assertEqual(restored.returncode, 0, restored.stderr)
        self.assertEqual(old.read_text(), new.read_text())

    def test_source_substitution_after_intent_stops_without_publishing(self):
        old = self.file(".old", "original")
        saved = self.home / "preserved-original"
        self.rule(".old", "new")
        journal = migrate.write_journal

        def substitute(log, event):
            journal(log, event)
            if event["event"] == "intent":
                old.rename(saved)
                old.write_text("late entry")

        with (patch.object(migrate, "write_journal", side_effect=substitute),
              self.assertRaisesRegex(migrate.Conflict, "source changed")):
            migrate.apply(self.manifest)
        self.assertFalse((self.home / "new").exists())
        self.assertEqual(saved.read_text(), "original")
        self.assertEqual(old.read_text(), "late entry")
        with self.assertRaises(migrate.Conflict):
            self.recover()

    def test_mount_identity_change_stops_before_a_move(self):
        old = self.file(".old", "original")
        self.rule(".old", "new")
        anchor = migrate.MoveBoundary.anchor
        calls = 0

        def changed(boundary, path):
            nonlocal calls
            calls += 1
            answer = anchor(boundary, path)
            if calls > 2:
                answer[-1] = "replacement"
            return answer

        with (patch.object(migrate.MoveBoundary, "anchor", changed),
              self.assertRaisesRegex(migrate.Conflict, "parent or mount changed")):
            migrate.apply(self.manifest)
        self.assertEqual(old.read_text(), "original")
        self.assertFalse((self.home / "new").exists())

    def test_custom_xdg_roots_and_json_only_legacy(self):
        self.file(".claude.json", '{"keep": true}')
        self.rule(".claude", "custom-config/claude")
        self.rule(".claude.json", "custom-config/claude/.claude.json")
        migrate.apply(self.manifest)
        self.assertEqual(json.loads((self.home / "custom-config/claude/.claude.json").read_text()),
                         {"keep": True})

    def test_interrupted_move_batch_can_be_retried(self):
        self.file(".first/key", "one")
        self.file(".second/key", "two")
        self.rule(".first", "first")
        self.rule(".second", "second")
        execute = migrate.safety.execute_move

        def interrupted(intent, **kwargs):
            if intent.source.name == ".second":
                raise OSError("simulated interruption")
            return execute(intent, **kwargs)

        with patch.object(migrate.safety, "execute_move", side_effect=interrupted):
            with self.assertRaises(OSError):
                migrate.apply(self.manifest)
        self.assertEqual((self.home / "first/key").read_text(), "one")
        self.assertTrue((self.home / ".second/key").exists())
        self.assertEqual([e["event"] for e in self.journal()], ["begin", "intent", "done", "intent"])
        with self.assertRaisesRegex(migrate.Conflict, "Recover outstanding run"):
            migrate.apply(self.manifest)
        self.recover()
        self.assertEqual((self.home / "second/key").read_text(), "two")

    def test_recovery_after_nested_parent_was_published(self):
        self.file(".bun/install/cache/key", "cached")
        self.file(".bun/bin/bun", "binary")
        self.rule(".bun/install/cache", "cache/bun/install")
        self.rule(".bun", "data/bun")
        write = migrate.write_journal

        def interrupt(log, event):
            if event["event"] == "done" and event["index"] == 1:
                raise OSError(errno.ENOSPC, "nested parent completion")
            write(log, event)

        with (patch.object(migrate, "write_journal", side_effect=interrupt),
              self.assertRaisesRegex(OSError, "nested parent completion")):
            migrate.apply(self.manifest)
        self.assertFalse((self.home / ".bun").exists())
        self.recover()
        self.assertEqual(self.journal()[-1]["event"], "finished")
        self.assertEqual((self.home / "cache/bun/install/key").read_text(), "cached")
        self.assertEqual((self.home / "data/bun/bin/bun").read_text(), "binary")

    def assert_home_group_recovery_preflights(self, mode):
        config = self.file(".claude/settings.json", "original")
        account = self.file(".claude.json", "original")
        self.rule(".claude", ".config/claude")
        self.rule(".claude.json", ".config/claude/.claude.json")
        run_id = None
        later = account
        if mode == "rollback":
            migrate.apply(self.manifest)
            run_id = self.journal()[0]["run"]
            later = self.home / ".config/claude/settings.json"
        _, state = migrate.manifest_paths(self.manifest)
        with (patch.object(migrate, "execute_run", side_effect=OSError("after durable group header")),
              self.assertRaisesRegex(OSError, "after durable group header")):
            migrate.mutate(self.manifest, mode, "fixture", {}, None, run_id=run_id, require_token=False)
        runs = migrate.read_runs(migrate.MoveBoundary(), state)
        pending, = [run for run in runs if not run["finished"]]
        self.assertEqual(pending["events"], [])
        header = pending["header"]
        operations = header["operations"]
        sources = [Path(operation["source"]) for operation in operations]
        destinations = [Path(operation["target"]) for operation in operations]
        identities = [migrate.identity(source.lstat()) for source in sources]
        journal = pending["path"] / "operations.jsonl"
        before = journal.read_bytes()

        info = later.stat()
        later.write_text("changed!")
        os.utime(later, ns=(info.st_atime_ns, info.st_mtime_ns))
        args = ("recover", "--group", "fixture", "--offline", "--run", header["run"])
        refused = self.invoke(*args)
        self.assertEqual(refused.returncode, 1, refused.stderr)
        self.assertIn("Payload changed after planning", refused.stderr)
        self.assertTrue(all(source.exists() for source in sources), "Recovery moved a pending source")
        self.assertEqual([migrate.identity(source.lstat()) for source in sources], identities)
        self.assertTrue(all(not destination.exists() for destination in destinations))
        self.assertEqual(later.read_text(), "changed!")
        self.assertEqual(journal.read_bytes(), before)

        later.write_text("original")
        os.utime(later, ns=(info.st_atime_ns, info.st_mtime_ns))
        resumed = self.invoke(*args)
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        if mode == "apply":
            config = self.home / ".config/claude/settings.json"
            account = self.home / ".config/claude/.claude.json"
        self.assertEqual([config.read_text(), account.read_text()], ["original", "original"])

    def test_home_group_recovery_preflights_apply(self):
        self.assert_home_group_recovery_preflights("apply")

    def test_home_group_recovery_preflights_rollback(self):
        self.assert_home_group_recovery_preflights("rollback")

    def test_home_group_recovery_after_scaffold_was_restored(self):
        record = self.file(".mozilla/firefox/places.sqlite", "profile")
        scaffold = self.home / ".config/mozilla/firefox/user.js"
        scaffold.parent.mkdir(parents=True)
        scaffold.symlink_to("/nix/store/nonexistent-home-manager-files/user.js")
        self.rule(".mozilla/firefox", ".config/mozilla/firefox")
        migrate.apply(self.manifest, generated={scaffold: {str(scaffold.readlink())}})
        transfer = self.journal()[0]["run"]
        write = migrate.write_journal

        def interrupt(log, event):
            if event["event"] == "done" and event["index"] == 1:
                raise OSError("after restoring scaffold")
            write(log, event)

        with (patch.object(migrate, "write_journal", side_effect=interrupt),
              self.assertRaisesRegex(OSError, "after restoring scaffold")):
            migrate.mutate(self.manifest, "rollback", "fixture", {}, None, run_id=transfer)
        runs = migrate.read_runs(migrate.MoveBoundary(), self.home / "state")
        pending, = [run for run in runs if not run["finished"]]
        self.assertEqual([event["event"] for event in pending["events"]], ["intent", "done", "intent"])
        self.assertTrue(scaffold.is_symlink())
        original = scaffold.lstat().st_ino
        resumed = self.invoke("recover", "--group", "fixture", "--offline", "--run", pending["header"]["run"])
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertEqual(scaffold.lstat().st_ino, original)
        self.assertEqual(record.read_text(), "profile")

    def test_unknown_absolute_self_symlinks_block(self):
        self.file(".old/key")
        (self.home / ".old/link").symlink_to(self.home / ".old/key")
        self.rule(".old", "new")
        with self.assertRaisesRegex(migrate.Conflict, "Absolute legacy-root"):
            migrate.plan(self.manifest)

    def test_unreadable_scaffolding_is_not_treated_as_empty(self):
        target = self.home / "generated"
        target.mkdir()
        with patch.object(migrate.os, "scandir", side_effect=PermissionError("unreadable")):
            with self.assertRaises(PermissionError):
                migrate.generated_tree(target, [target / "managed"])

    def test_internal_relative_link_to_store_link_is_preserved(self):
        self.file(".cargo/bin/other")
        binary = self.home / ".cargo/bin/rustup"
        binary.symlink_to("/nix/store/nonexistent-rustup/bin/rustup")
        (binary.parent / "cargo").symlink_to("rustup")
        self.rule(".cargo", ".local/share/cargo")
        migrate.apply(self.manifest)
        self.assertEqual(os.readlink(self.home / ".local/share/cargo/bin/cargo"), "rustup")

    def test_non_directory_future_parent_blocks_entire_batch(self):
        self.file(".first/key")
        self.file(".claude", "unexpected file instead of directory")
        self.file(".claude.json", "{}")
        self.rule(".first", "first")
        self.rule(".claude", ".config/claude")
        self.rule(".claude.json", ".config/claude/.claude.json")
        with self.assertRaisesRegex(migrate.Conflict, "parent is not a directory"):
            migrate.apply(self.manifest)
        self.assertTrue((self.home / ".first/key").exists())
        self.assertFalse((self.home / "state").exists())

    def test_bun_link_requires_manual_review_before_a_move(self):
        package = self.file(".bun/install/cache/cli-width@4/package.json", "legacy")
        alias = self.home / ".bun/install/cache/cli-width/4"
        alias.parent.mkdir(parents=True)
        alias.symlink_to(package.parent)
        inode = package.stat().st_ino
        self.file(".bun/bin/bun", "binary")
        self.rule(".bun/install/cache", ".cache/bun/install", owner="home-layout", repairAbsoluteLinks=True)
        self.rule(".bun", ".local/share/bun", owner="home-layout", repairAbsoluteLinks=True)

        before = migrate.plan(self.manifest)
        self.assertTrue(any(a["action"] == "symlink" for a in before))
        self.assertEqual(os.readlink(alias), str(package.parent))
        review = self.invoke("check")
        self.assertEqual(review.returncode, 0, review.stderr)
        self.assertIn('"symlink"', review.stdout)
        self.assertIn("operator review", review.stderr)
        with self.assertRaises(migrate.Unsupported):
            migrate.apply(self.manifest)
        self.assertFalse((self.home / "state").exists())

        # Simulate an operator who preserved the original link and reviewed the
        # final absolute target while both cache locations were offline.
        alias.rename(self.home / "saved-bun-alias")
        repaired = self.home / ".cache/bun/install/cli-width@4"
        alias.symlink_to(repaired)
        migrate.apply(self.manifest)
        new_alias = self.home / ".cache/bun/install/cli-width/4"
        self.assertEqual(new_alias.readlink(), repaired)
        self.assertEqual((new_alias / "package.json").stat().st_ino, inode)
        self.assertEqual(migrate.plan(self.manifest), [])

    def test_cache_collisions_preserve_both_even_for_old_backup_flag(self):
        for source, target, owner in [
            (".bun/install/cache", ".cache/bun/install", "home-layout"),
            (".npm", ".cache/npm", "common"),
        ]:
            with self.subTest(owner=owner):
                old = self.file(f"{source}/entry", "old")
                new = self.file(f"{target}/entry", "new")
                before = [path.stat().st_ino for path in (old, new)]
                self.rule(source, target, owner=owner, onConflict="backup")
                result = self.invoke("check")
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("Both paths contain data", result.stderr)
                self.assertIn(owner, result.stderr)
                with self.assertRaises(migrate.Conflict):
                    migrate.apply(self.manifest)
                self.assertEqual([path.stat().st_ino for path in (old, new)], before)
                self.assertEqual([path.read_text() for path in (old, new)], ["old", "new"])
                self.assertFalse((self.home / "state").exists())
                self.manifest["rules"].clear()

    def test_apparent_match_remains_a_conflict_even_with_corrupt_history(self):
        old = self.file(".old/key", "private data")
        new = self.file(".new/key", "private data")
        for path in (old, new, old.parent, new.parent):
            os.utime(path, (100, 100))
        before = [path.stat() for path in (old, new)]
        self.rule(".old", ".new")
        journal = self.file("state/old-run/operations.jsonl", '{"action": "move"\n')
        journal.parent.parent.chmod(0o700)
        result = self.invoke("check")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Unexpected entry in migration journal", result.stderr)
        self.assertNotIn("private data", result.stderr)
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)
        self.assertEqual([path.stat() for path in (old, new)], before)
        self.assertEqual(journal.read_text(), '{"action": "move"\n')
        self.assertEqual(list(journal.parent.parent.iterdir()), [journal.parent])

    def test_comparison_detects_equal_size_content_and_mode_differences(self):
        old = self.file(".old", "abcdef")
        new = self.file(".new", "ABCDEF")
        self.rule(".old", ".new")

        def differs():
            for path in (old, new):
                os.utime(path, (100, 100))
            result = self.invoke("check")
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("Both paths contain data and differ", result.stderr)
            self.assertNotIn("ABCDEF", result.stderr)
        differs()
        new.write_text(old.read_text())
        new.chmod(0o640)
        differs()
        self.assertFalse((self.home / "state").exists())

    def test_unavailable_metadata_cannot_authorize_comparison_or_scaffolding(self):
        old = self.file(".old/key")
        target = self.home / ".new/user.js"
        target.parent.mkdir()
        target.symlink_to("/nix/store/nonexistent-home-manager-files/user.js")
        self.rule(".old", ".new")
        self.manifest["managed"] = [str(target)]
        with (patch.object(migrate.os, "listxattr", side_effect=OSError(errno.ENOTSUP, "no xattrs")),
              self.assertRaises(OSError) as failure):
            migrate.apply(self.manifest, generated={target: {str(target.readlink())}})
        self.assertEqual(failure.exception.errno, errno.ENOTSUP)
        self.assertTrue(target.is_symlink())

        new = self.file("other/key")
        self.manifest["rules"].clear()
        self.rule(".old/key", "other/key")
        for path in (old, new):
            os.utime(path, (100, 100))
        with patch.object(migrate.os, "listxattr", side_effect=OSError(errno.ENOTSUP, "no xattrs")):
            with self.assertRaisesRegex(migrate.Conflict, "comparison could not establish a match"):
                migrate.plan(self.manifest, compare_collisions=True)
        self.assertFalse((self.home / "state").exists())

    def test_comparison_checks_xattrs_when_supported(self):
        old = self.file(".old", "same")
        new = self.file(".new", "same")
        self.rule(".old", ".new")
        try:
            os.setxattr(new, "user.fixture", b"private metadata")
        except OSError as error:
            if error.errno != errno.ENOTSUP:
                raise
            self.skipTest("fixture filesystem does not support user xattrs")
        for path in (old, new):
            os.utime(path, (100, 100))
        result = self.invoke("check")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Both paths contain data and differ", result.stderr)
        self.assertNotIn("private metadata", result.stderr)

    def test_comparison_refuses_link_identity_and_special_entries(self):
        self.rule(".old", ".new")
        old = self.file(".old/key", "same")
        new = self.file(".new/key", "same")

        def cannot_establish():
            for path in (old.parent, new.parent, old, new):
                os.utime(path, (100, 100), follow_symlinks=False)
            result = self.invoke("check")
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("comparison could not establish a match", result.stderr)
        os.link(old, self.home / "another-hardlink")
        cannot_establish()
        for path in (old, new):
            path.unlink()
            path.symlink_to(path.parent)
        cannot_establish()
        for path in (old, new):
            path.unlink()
            os.mkfifo(path)
        cannot_establish()
        self.assertFalse((self.home / "state").exists())

    def test_comparison_refuses_live_nonparticipating_writer(self):
        old = self.file(".old", "first")
        self.file(".new", "first")
        self.rule(".old", ".new")
        for name in (".old", ".new"):
            os.utime(self.home / name, (100, 100))
        read = os.read
        changed = False

        def race(fd, size):
            nonlocal changed
            chunk = read(fd, size)
            if not changed:
                changed = True
                subprocess.run([sys.executable, "-c",
                                "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('other')",
                                str(old)], check=True)
                os.utime(old, (100, 100))
            return chunk

        with patch.object(migrate.os, "read", side_effect=race):
            with self.assertRaisesRegex(migrate.Conflict, "comparison could not establish a match"):
                migrate.plan(self.manifest, compare_collisions=True)
        self.assertTrue(changed)
        self.assertEqual(old.read_text(), "other")
        self.assertEqual((self.home / ".new").read_text(), "first")
        self.assertFalse((self.home / "state").exists())

    def test_comparison_refuses_unreadable_subtree(self):
        old = self.file(".old/sub/key")
        new = self.file(".new/sub/key")
        self.rule(".old", ".new")
        for path in (old.parent, new.parent):
            path.chmod(0)
            self.addCleanup(path.chmod, 0o700)
        for path in (old.parent, new.parent, old.parent.parent, new.parent.parent):
            os.utime(path, (100, 100))
        result = self.invoke("check")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("comparison could not establish a match (PermissionError)", result.stderr)

    def test_activation_distinguishes_held_pending_and_unverified_redirect(self):
        old = self.file(".old/key", "private fixture")
        before = old.stat()
        rule = self.rule(".old", ".new", owner="firefox", processes=["*"], route=str(old.parent))
        self.manifest["adopt"] = {"firefox": "legacy"}
        errors = io.StringIO()
        with (patch.object(migrate, "generation_files", return_value={}),
              patch.object(migrate, "busy", side_effect=AssertionError("activation scans writers")),
              redirect_stderr(errors)):
            generation = Path("/fixture-generation")
            migrate.activation_gate(self.manifest, migrate.MoveBoundary(), generation, None, None, False)
            rule["route"] = rule["target"]
            with self.assertRaisesRegex(migrate.Conflict, "intended route requires a verified transfer"):
                migrate.activation_gate(self.manifest, migrate.MoveBoundary(), generation, None, None, False)
        self.assertIn("[firefox] migration assessment: legacy pending", errors.getvalue())
        self.assertIn("runtime continuity: legacy held", errors.getvalue())
        self.assertNotIn("private fixture", errors.getvalue())
        self.assertEqual(old.stat().st_ino, before.st_ino)
        self.assertFalse((self.home / ".new").exists())
        self.assertFalse((self.home / "state").exists())

    def test_activation_retains_a_specific_managed_link_blocker(self):
        body = self.file(".old/profile.js", "private profile")
        self.rule(".old", ".new", owner="firefox", route=str(body.parent))
        self.manifest["adopt"] = {"firefox": "legacy"}
        generated = {body: {"/nix/store/fixture-home-manager-files/.old/profile.js"}}
        with (patch.object(migrate, "generation_files", return_value=generated),
              self.assertRaisesRegex(migrate.Conflict, "Home Manager link would displace protected data")):
            migrate.activation_gate(self.manifest, migrate.MoveBoundary(), Path("/fixture-generation"),
                                    None, None, False)
        self.assertEqual(body.read_text(), "private profile")

    def test_restored_payload_admits_native_legacy_route_under_exclusion(self):
        source = self.file(".old/marker", "original")
        rule = self.rule(".old", ".new")
        migrate.apply(self.manifest)
        run = self.journal()[0]["run"]
        incumbent = self.home / "installed-generation"
        incumbent.mkdir()
        (incumbent / "home-layout-manifest.json").write_text(json.dumps(self.manifest))
        rule["route"] = rule["source"]
        generation = Path("/fixture-generation")
        with patch.object(migrate, "generation_files", return_value={}):
            with self.assertRaisesRegex(migrate.Conflict, "no verified legacy incumbent"):
                migrate.activation_gate(self.manifest, migrate.MoveBoundary(), generation, None, incumbent, False)
            migrate.mutate(self.manifest, "rollback", "fixture", {}, None, run_id=run)
            with self.assertRaisesRegex(migrate.Conflict, "exclude active sessions and writers before rollback"):
                migrate.activation_gate(self.manifest, migrate.MoveBoundary(), generation, None, incumbent, True)
            migrate.activation_gate(self.manifest, migrate.MoveBoundary(), generation, None, incumbent, False)
        self.assertEqual(source.read_text(), "original")
        self.assertFalse((self.home / ".new").exists())

    def test_xdg_redirect_assesses_populated_incumbent_with_empty_candidate_roots(self):
        old_record = self.file("previous-xdg/codex/record", "incumbent data")
        rule = self.rule(".codex", "previous-xdg/codex", owner="codex")
        incumbent = self.home / "installed-generation"
        incumbent.mkdir()
        (incumbent / "home-layout-manifest.json").write_text(json.dumps(self.manifest))
        rule["target"] = str(self.home / "different-xdg/codex")
        generation = Path("/fixture-generation")
        with patch.object(migrate, "generation_files", return_value={}):
            with self.assertRaisesRegex(migrate.Conflict, "exclude active sessions and writers before cutover"):
                migrate.activation_gate(self.manifest, migrate.MoveBoundary(), generation, None, incumbent, True)
            with self.assertRaisesRegex(migrate.Conflict, "intended route requires a verified transfer"):
                migrate.activation_gate(self.manifest, migrate.MoveBoundary(), generation, None, incumbent, False)
        self.assertEqual(old_record.read_text(), "incumbent data")
        self.assertFalse(Path(rule["target"]).exists())

    def test_cross_rule_absolute_link_proposal_uses_specific_target(self):
        cache = self.file('.bun/install/cache/cli-width@4.1.0@@@1/package', 'legacy')
        link = self.home / '.bun/bin/cli'
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(cache)
        self.rule('.bun/install/cache', '.cache/bun/install', repairAbsoluteLinks=True)
        self.rule('.bun', '.local/share/bun', repairAbsoluteLinks=True)
        new_link = self.home / '.local/share/bun/bin/cli'
        repair, = [a for a in migrate.plan(self.manifest) if a['action'] == 'symlink']
        self.assertEqual(repair['current'], str(link))
        self.assertEqual(repair['target'], str(new_link))
        self.assertEqual(repair['replacement'], os.path.relpath(
            self.home / '.cache/bun/install/cli-width@4.1.0@@@1/package', new_link.parent))
        with self.assertRaises(migrate.Unsupported):
            migrate.apply(self.manifest)
        self.assertEqual(link.read_text(), 'legacy')
        self.assertFalse(new_link.exists())
        self.assertFalse((self.home / 'state').exists())

    def test_old_interrupted_link_repair_is_diagnosed_without_mutation(self):
        target = self.file('.new/package', 'value')
        new_link = target.with_name('alias')
        old_target = self.home / '.old/package'
        new_link.symlink_to(old_target)
        inode = new_link.lstat().st_ino
        self.rule('.old', '.new', repairAbsoluteLinks=True)
        action, = migrate.plan(self.manifest)
        self.assertEqual(action['current'], str(new_link))
        self.assertEqual(action['replacement'], 'package')
        with self.assertRaises(migrate.Unsupported):
            migrate.apply(self.manifest)
        self.assertEqual(os.readlink(new_link), str(old_target))
        self.assertEqual(new_link.lstat().st_ino, inode)
        self.assertEqual(target.read_text(), 'value')
        self.assertFalse((self.home / 'state').exists())

    def test_non_opted_absolute_link_still_blocked(self):
        target = self.file('.old/key')
        (self.home / '.old/link').symlink_to(target)
        self.rule('.old', '.new')
        with self.assertRaisesRegex(migrate.Conflict, 'Absolute legacy-root'):
            migrate.apply(self.manifest)

    def test_external_link_untouched(self):
        self.file('.old/key')
        (self.home / '.old/link').symlink_to('/nix/store/not-present/file')
        self.rule('.old', '.new', repairAbsoluteLinks=True)
        migrate.apply(self.manifest)
        self.assertEqual(os.readlink(self.home / '.new/link'), '/nix/store/not-present/file')

    def test_collision_rejects_symlink_or_file_destination(self):
        self.file('.old/key')
        self.file('other/key')
        target = self.home / '.new'
        target.symlink_to('other')
        self.rule('.old', '.new', onConflict='backup')
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)
        self.assertTrue(target.is_symlink())
        self.assertFalse((self.home / 'state').exists())
        target.unlink()
        target.write_text('real')
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)
        self.assertEqual(target.read_text(), 'real')

    def test_require_noop_guard_blocks_pending_move_before_writes(self):
        self.file(".old/credential", "secret")
        self.rule(".old", ".new")
        manifest = self.home / "manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        output = io.StringIO()
        errors = io.StringIO()
        with patch("sys.argv", ["migrate", "--manifest", str(manifest),
                                "--require-noop", "check"]):
            with redirect_stdout(output), redirect_stderr(errors):
                status = migrate.main()
        self.assertEqual(status, 2)
        self.assertIn("pending", errors.getvalue())
        self.assertTrue((self.home / ".old/credential").exists())
        self.assertFalse((self.home / ".new").exists())
        self.assertFalse((self.home / "state").exists())

    def test_require_noop_guard_accepts_empty_plan(self):
        self.rule(".old", ".new")
        manifest = self.home / "manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        with patch("sys.argv", ["migrate", "--manifest", str(manifest),
                                "--require-noop", "check"]):
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(migrate.main(), 0)
        self.assertFalse((self.home / "state").exists())

    def test_require_noop_guard_cannot_be_combined_with_apply(self):
        self.file(".old/key")
        self.rule(".old", ".new")
        manifest = self.home / "manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        with patch("sys.argv", ["migrate", "--manifest", str(manifest),
                                "--require-noop", "apply"]):
            with redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    migrate.main()
        self.assertTrue((self.home / ".old/key").exists())
        self.assertFalse((self.home / "state").exists())

    def test_reference_diagnostic_refuses_entire_batch_and_keeps_contents_private(self):
        first = self.file(".first/key")
        self.rule(".first", "first")
        reference = self.file(".codex/config.toml", 'path = "~/.codex/tool"\nsecret = "private fixture"')
        self.rule(".codex", "xdg/codex", references=["config.toml"])
        before = reference.stat()
        result = self.invoke("check", "--require-noop")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("operator review", result.stderr)
        self.assertIn("rewrite", result.stdout)
        result = self.invoke("apply", "--group", "fixture", "--offline")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("batch refused", result.stderr)
        self.assertNotIn("private fixture", result.stdout + result.stderr)
        self.assertTrue(first.exists())
        self.assertEqual(reference.stat().st_ino, before.st_ino)
        self.assertFalse((self.home / "first").exists())
        self.assertFalse((self.home / "state").exists())

    def launch(self, *args):
        launcher = os.environ.get("MIGRATE_LAUNCHER")
        command = [launcher] if launcher else [sys.executable, migrate.__file__, "--manifest", "/proc/self/fd/0",
                                                 "--rsync", shutil.which("rsync") or "rsync"]
        return subprocess.run(command + list(args), input=json.dumps(self.manifest),
                              capture_output=True, text=True, check=False)

    def invoke(self, *args):
        if not (self.sandbox_root or self.sandbox_xattr_listing):
            return self.launch(*args)
        manifest = self.home / "fixture-manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        stdout, stderr = io.StringIO(), io.StringIO()
        with (patch.object(sys, "argv", ["migrate", "--manifest", str(manifest), *args]),
              redirect_stdout(stdout), redirect_stderr(stderr)):
            status = migrate.main()
        return subprocess.CompletedProcess(args, status, stdout.getvalue(), stderr.getvalue())

    def test_real_launcher_read_only_startup(self):
        self.rule(".absent", "xdg/new")
        result = self.launch("check", "--require-noop")
        if self.sandbox_root:
            self.assertEqual(result.returncode, 1, result.stderr)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "[]")
        self.assertFalse((self.home / "state").exists())
        if self.sandbox_root:
            self.file(".absent/key")
            result = self.launch("apply", "--group", "fixture", "--offline")
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("untrusted entry changes: /", result.stderr)
            self.assertFalse((self.home / "state").exists())

    def test_packaged_entrypoint_checks_applies_and_becomes_noop(self):
        original = self.file(".old/key")
        inode = original.stat().st_ino
        self.rule(".old", "xdg/new")
        check = self.invoke("check", "--require-noop")
        self.assertEqual(check.returncode, 2, check.stderr)
        self.assertFalse((self.home / "state").exists())
        self.assertTrue(original.exists())
        plan = self.invoke("plan", "--group", "fixture")
        token = json.loads(plan.stdout)["expect"]
        applied = self.invoke("apply", "--group", "fixture", "--offline", "--expect", token)
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertFalse(original.exists())
        self.assertEqual((self.home / "xdg/new/key").stat().st_ino, inode)
        check = self.invoke("check", "--require-noop")
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertEqual(check.stdout.strip(), "[]")

    def test_same_home_lock_rejects_competing_open_without_state(self):
        old = self.file(".old/key")
        self.rule(".old", "new")
        fd = os.open(self.home, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.invoke("check", "--require-noop").returncode, 2)
            result = self.invoke("apply", "--group", "fixture", "--offline")
            self.assertEqual(result.returncode, 1)
            self.assertIn("HOME lock", result.stderr)
        finally:
            os.close(fd)
        self.assertTrue(old.exists())
        self.assertFalse((self.home / "state").exists())

    def test_unsupported_boundaries_are_read_only(self):
        old = self.file(".old/key")
        self.rule(".old", "new")
        outside = self.home / "other"
        outside.mkdir()
        alias = self.home / "alias"
        alias.symlink_to(outside)
        rule = self.rule(".later", "alias/dest")
        self.file(".later/key")
        for target in (str(alias / "dest"), str(self.home / "other/../dest")):
            with self.subTest(target=target):
                rule["target"] = target
                with self.assertRaises(migrate.Unsupported):
                    migrate.apply(self.manifest)
                self.assertTrue(old.exists())
                self.assertFalse((self.home / "state").exists())
                self.assertEqual(list(outside.iterdir()), [])
        rule["target"] = str(outside / "dest")
        outside.chmod(0o777)
        with self.assertRaisesRegex(migrate.Unsupported, "untrusted entry changes"):
            migrate.apply(self.manifest)
        self.assertFalse((self.home / "state").exists())

    def test_unsupported_filesystem_blocks_before_first_move(self):
        old = self.file(".old/key")
        self.rule(".old", "target")
        with patch("move_boundary.LOCAL_FILESYSTEMS", set()):
            with self.assertRaisesRegex(migrate.Unsupported, "Unsupported migration filesystem"):
                migrate.apply(self.manifest)
        self.assertTrue(old.exists())
        self.assertFalse((self.home / "state").exists())

    def test_full_journal_filesystem_cannot_commit_a_move(self):
        old = self.file(".old/key")
        before = old.stat()
        self.rule(".old", ".new")
        with (patch.object(migrate, "write_journal", side_effect=OSError(errno.ENOSPC, "journal full")),
              patch.object(migrate.safety, "execute_move") as execute,
              self.assertRaises(OSError) as failure):
            migrate.apply(self.manifest)
        self.assertEqual(failure.exception.errno, errno.ENOSPC)
        execute.assert_not_called()
        self.assertEqual(old.stat().st_ino, before.st_ino)
        self.assertFalse((self.home / ".new").exists())

    def test_intent_flush_failure_can_leave_a_record_but_does_not_rename(self):
        original = self.file(".old")
        self.rule(".old", "xdg/new")
        journal = migrate.write_journal

        def fail_intent(log, event):
            if event["event"] != "intent":
                return journal(log, event)
            with patch.object(migrate.os, "fsync", side_effect=OSError(errno.ENOSPC, "journal flush")):
                journal(log, event)

        with (patch.object(migrate, "write_journal", side_effect=fail_intent),
              patch.object(migrate.safety, "execute_move") as execute):
            with self.assertRaisesRegex(OSError, "journal flush"):
                migrate.apply(self.manifest)
        execute.assert_not_called()
        begin, event = self.journal()
        self.assertEqual(event["event"], "intent")
        self.assertEqual(event["entry"][1], original.stat().st_ino)
        self.assertFalse((self.home / "xdg/new").exists())

    def test_backup_parent_flush_failure_leaves_visible_archive_and_legacy(self):
        old = self.file(".old/key", "legacy")
        target = self.home / "xdg/new/user.js"
        target.parent.mkdir(parents=True)
        link = "/nix/store/nonexistent-home-manager-files/user.js"
        target.symlink_to(link)
        legacy_inode, cache_inode = old.stat().st_ino, target.lstat().st_ino
        self.rule(".old", "xdg/new")
        self.manifest["managed"] = [str(target)]
        execute = migrate.safety.execute_move
        flushes = []

        def failed_backup_flush(intent, **kwargs):
            def fail(fd):
                flushes.append(fd)
                raise OSError(errno.EIO, "backup directory flush")
            with patch.object(migrate.os, "fsync", side_effect=fail):
                try:
                    return execute(intent, **kwargs)
                finally:
                    self.assertEqual(flushes, [intent.target.parent_fd])

        with patch.object(migrate.safety, "execute_move", side_effect=failed_backup_flush):
            with self.assertRaisesRegex(migrate.safety.OutcomeUnknown, "parent flush failed"):
                migrate.apply(self.manifest, generated={target: {link}})
        begin, event = self.journal()
        self.assertEqual(event["event"], "intent")
        self.assertEqual(begin["operations"][0]["kind"], "scaffold")
        self.assertFalse(target.is_symlink())
        backup = Path(event["target"]) / "user.js"
        self.assertEqual(backup.lstat().st_ino, cache_inode)
        self.assertEqual(str(backup.readlink()), link)
        self.assertEqual(old.stat().st_ino, legacy_inode)
        self.recover()
        self.assertEqual(target.with_name("key").stat().st_ino, legacy_inode)
        self.assertEqual(backup.lstat().st_ino, cache_inode)

    def test_completion_failure_follows_both_parent_flushes(self):
        old = self.file(".old", "data")
        inode = old.stat().st_ino
        self.rule(".old", "deep/target")
        journal, fsync = migrate.write_journal, os.fsync
        observed = []

        def track(fd):
            observed.append(Path(os.readlink(f"/proc/self/fd/{fd}")))
            return fsync(fd)

        def completion(log, event):
            if event["event"] == "done":
                self.assertEqual(observed[-2:], [self.home / "deep", self.home])
                raise OSError(errno.ENOSPC, "completion flush failed")
            journal(log, event)

        with (patch.object(migrate, "write_journal", side_effect=completion),
              patch.object(migrate.os, "fsync", side_effect=track)):
            with self.assertRaises(OSError) as failure:
                migrate.apply(self.manifest)
        self.assertEqual(failure.exception.errno, errno.ENOSPC)
        self.assertFalse(old.exists())
        target = self.home / "deep/target"
        self.assertEqual(target.stat().st_ino, inode)
        self.assertEqual(target.read_text(), "data")
        begin, event = self.journal()
        self.assertEqual(event["event"], "intent")
        self.assertEqual(event["entry"][1], inode)
        run = begin["run"]
        recovered = self.invoke("recover", "--group", "fixture", "--offline", "--run", run)
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assertEqual(self.journal()[-1]["event"], "finished")
        self.assertEqual(migrate.plan(self.manifest), [])


if __name__ == "__main__":
    unittest.main()
