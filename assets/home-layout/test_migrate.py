"""Data-preservation regression tests; fixtures never touch the real home."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "migrate", os.environ.get("MIGRATE_SOURCE", str(Path(__file__).with_name("migrate.py"))))
migrate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migrate)


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.manifest = {"home": str(self.home), "state": str(self.home / "state"),
                         "rules": [], "managed": []}

    def file(self, relative, content="credentials", mode=0o600):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(mode)
        return path

    def rule(self, source, target, **extra):
        rule = {"source": str(self.home / source), "target": str(self.home / target), **extra}
        self.manifest["rules"].append(rule)
        return rule

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
        migrate.apply(self.manifest)
        self.assertEqual((scaffolding.parent / "places.sqlite").read_text(), "bookmarks")
        saved = list((self.home / "state").glob("*/scaffolding/0/default/user.js"))
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

    def test_reference_repair_is_backed_up_and_resumes_after_directory_move(self):
        # Simulate a prior run interrupted after rename but before reference repair.
        old = self.home / ".codex"
        original = json.dumps({"command": f"{old}/hook.sh", "other": f"{old}-other/keep"})
        self.file(".local/share/codex/hooks.json", original)
        self.rule(".codex", ".local/share/codex", references=["hooks.json"])
        migrate.apply(self.manifest)
        result = json.loads((self.home / ".local/share/codex/hooks.json").read_text())
        self.assertEqual(result["command"], str(self.home / ".local/share/codex/hook.sh"))
        self.assertEqual(result["other"], f"{old}-other/keep")
        backup = list((self.home / "state").glob("*/references/*"))[0]
        self.assertEqual(backup.read_text(), original)
        self.assertEqual(migrate.apply(self.manifest), [])

    def test_atomic_rename_never_overwrites_even_an_empty_directory(self):
        source = self.home / "source"
        target = self.home / "target"
        source.mkdir()
        target.mkdir()
        with self.assertRaises(OSError):
            migrate.rename_noreplace(source, target)
        self.assertTrue(source.is_dir())
        self.assertTrue(target.is_dir())

    def test_cross_filesystem_requires_manual_migration(self):
        self.file(".old/key")
        self.rule(".old", "other-disk/new")
        other_disk = SimpleNamespace(stat=lambda: SimpleNamespace(st_dev=-1), is_dir=lambda: True)
        with patch.object(migrate, "nearest", return_value=other_disk):
            with self.assertRaisesRegex(migrate.Conflict, "Cross-filesystem"):
                migrate.apply(self.manifest)
        self.assertFalse((self.home / "state").exists())

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
        rename = migrate.rename_noreplace

        def interrupted(source, target):
            if source == self.home / ".second":
                raise OSError("simulated interruption")
            return rename(source, target)

        with patch.object(migrate, "rename_noreplace", side_effect=interrupted):
            with self.assertRaises(OSError):
                migrate.apply(self.manifest)
        self.assertEqual((self.home / "first/key").read_text(), "one")
        self.assertTrue((self.home / ".second/key").exists())
        migrate.apply(self.manifest)
        self.assertEqual((self.home / "second/key").read_text(), "two")

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
                migrate.generated_tree(target)

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

    def test_bun_link_rewrite_and_backup_both_caches(self):
        package = self.file('.bun/install/cache/cli-width@4.1.0@@@1/package.json', 'legacy')
        alias = self.home / '.bun/install/cache/cli-width/4.1.0@@@1'
        alias.parent.mkdir(parents=True)
        alias.symlink_to(package.parent)
        inode = package.stat().st_ino
        self.file('.cache/bun/install/new-cache', 'new')
        self.file('.bun/bin/bun', 'binary')
        self.rule('.bun/install/cache', '.cache/bun/install', onConflict='backup', repairAbsoluteLinks=True)
        self.rule('.bun', '.local/share/bun', repairAbsoluteLinks=True)
        before = migrate.plan(self.manifest)
        self.assertTrue(any(a['action'] == 'symlink' for a in before))
        self.assertEqual(os.readlink(alias), str(package.parent))  # check must not mutate
        self.assertEqual((self.home / '.cache/bun/install/new-cache').read_text(), 'new')
        migrate.apply(self.manifest)
        new_alias = self.home / '.cache/bun/install/cli-width/4.1.0@@@1'
        self.assertEqual(os.readlink(new_alias), '../cli-width@4.1.0@@@1')
        self.assertEqual((new_alias / 'package.json').read_text(), 'legacy')
        self.assertEqual((self.home / '.cache/bun/install/cli-width@4.1.0@@@1/package.json').stat().st_ino, inode)
        backups = list((self.home / 'state').glob('*/conflicts/0/new-cache'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), 'new')
        self.assertEqual(migrate.plan(self.manifest), [])

    def test_backup_optin_only(self):
        self.file('.old/a', 'old')
        self.file('.new/b', 'new')
        self.rule('.old', '.new')
        with self.assertRaisesRegex(migrate.Conflict, 'Both paths contain data'):
            migrate.apply(self.manifest)
        self.assertFalse((self.home / 'state').exists())

    def test_no_moves_if_another_rule_conflicts_after_backup_policy(self):
        self.file('.bun/install/cache/a')
        self.file('.cache/bun/install/b')
        self.file('.claude/key')
        self.file('.config/claude/other')
        self.rule('.bun/install/cache', '.cache/bun/install', onConflict='backup', repairAbsoluteLinks=True)
        self.rule('.claude', '.config/claude')
        with self.assertRaises(migrate.Conflict):
            migrate.apply(self.manifest)
        self.assertTrue((self.home / '.bun/install/cache/a').exists())
        self.assertTrue((self.home / '.cache/bun/install/b').exists())
        self.assertFalse((self.home / 'state').exists())

    def test_cross_rule_absolute_link_uses_specific_target(self):
        cache = self.file('.bun/install/cache/cli-width@4.1.0@@@1/package', 'legacy')
        link = self.home / '.bun/bin/cli'
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(cache)
        self.rule('.bun/install/cache', '.cache/bun/install', repairAbsoluteLinks=True)
        self.rule('.bun', '.local/share/bun', repairAbsoluteLinks=True)
        migrate.apply(self.manifest)
        new_link = self.home / '.local/share/bun/bin/cli'
        self.assertEqual(new_link.read_text(), 'legacy')
        self.assertEqual(os.readlink(new_link), os.path.relpath(self.home / '.cache/bun/install/cli-width@4.1.0@@@1/package',new_link.parent))

    def test_interrupted_after_move_repairs_on_retry(self):
        target = self.file('.old/package', 'value')
        original_link = self.home / '.old/alias'
        original_link.symlink_to(target)
        self.rule('.old', '.new', repairAbsoluteLinks=True)
        original_symlink = migrate.os.symlink
        def crash_rewrite(value, path, *args, **kwargs):
            if '.home-migration-link-' in str(path):
                raise OSError('simulated crash')
            return original_symlink(value, path, *args, **kwargs)
        with patch.object(migrate.os, 'symlink', side_effect=crash_rewrite):
            with self.assertRaisesRegex(OSError, 'simulated crash'):
                migrate.apply(self.manifest)
        self.assertFalse((self.home / '.old').exists())
        new_link = self.home / '.new/alias'
        self.assertEqual(os.readlink(new_link), str(target))
        migrate.apply(self.manifest)
        self.assertEqual(os.readlink(new_link), 'package')
        self.assertEqual(new_link.read_text(), 'value')
        self.assertEqual(migrate.apply(self.manifest), [])

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

    def test_backup_rejects_symlink_or_file_destination(self):
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


if __name__ == "__main__":
    unittest.main()
