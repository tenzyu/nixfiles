#!/usr/bin/env python3
"""Regression tests for the selective CI contract."""

import importlib.util
import pathlib
import subprocess
import sys
import unittest
from io import StringIO
from contextlib import redirect_stdout, redirect_stderr
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).with_name("select-checks.py")
spec = importlib.util.spec_from_file_location("select_checks", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class SelectionTests(unittest.TestCase):
    def test_unrelated_docs_are_baseline_only(self):
        self.assertEqual(module.selection(["README.md", "docs/index.md"]), ([], False))

    def test_home_layout_is_scoped(self):
        self.assertEqual(module.selection(["assets/home-layout/migrate.py"]), (["home-migration"], False))

    def test_store_clean_is_scoped(self):
        self.assertEqual(module.selection(["modules/50-features/nix/nix-store-clean.nix"]), (["nix-store-clean"], False))

    def test_safety_python_check_is_scoped(self):
        for path in (
            "assets/safety/python/test_operations.py",
            "modules/10-foundations/safety-python-check.nix",
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), (["safety-python"], False))

    def test_python_move_core_also_checks_the_home_consumer(self):
        for path in ("assets/safety/python/safety_operations.py", "assets/safety/python/default.nix"):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), (["home-migration", "safety-python"], False))

    def test_opencode_is_scoped(self):
        self.assertEqual(module.selection(["assets/opencode/direnv.ts"]), (["opencode-direnv"], False))

    def test_rtk_is_scoped(self):
        self.assertEqual(module.selection(["modules/50-features/development/rtk.nix"]), (["rtk-rewrites"], False))

    def test_steam_lifecycle_checks_are_change_scoped(self):
        self.assertEqual(module.selection(["modules/50-features/gaming/steam.nix"]), (["steam-gaming"], False))
        self.assertEqual(module.selection(["assets/steam-gaming/test-launch.sh"]), (["steam-gaming"], False))

    def test_lock_update_checks_dependency_sensitive_modules(self):
        self.assertEqual(module.selection(["flake.lock"]), (sorted(module.OPTIONAL_CHECKS), True))

    def test_splitcast_private_cache_policy_triggers_audit(self):
        self.assertEqual(
            module.selection(["modules/50-features/media/_internal/cache.nix"]),
            ([], True),
        )

    def test_splitcast_only_runs_cache_probe(self):
        self.assertEqual(module.selection(["modules/50-features/media/splitcast-production.nix"]), ([], True))

    def test_nix_settings_changes_probe_cache(self):
        self.assertEqual(module.selection(["modules/50-features/nix/nix.nix"]), ([], True))

    def test_cache_probe_script_change_triggers_probe(self):
        self.assertEqual(module.selection(["scripts/ci/audit-splitcast-cache.sh"]), ([], True))

    def test_dedup_and_order_are_stable(self):
        self.assertEqual(
            module.selection(["assets/opencode/direnv.ts", "flake.nix", "assets/opencode/direnv.test.ts"]),
            (sorted(module.OPTIONAL_CHECKS), True),
        )

    def test_shared_sources_select_all_focused_checks(self):
        for path in (
            "modules/10-foundations/overlays.nix",
            "modules/00-hosts/neko5/configuration.nix",
            "modules/_internal/configurations/lib/seed.nix",
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), (sorted(module.OPTIONAL_CHECKS), True))

    def test_test_sources_do_not_force_unrelated_feature_checks(self):
        self.assertEqual(module.selection([
            "modules/_internal/configurations/tests/trace.nix",
            "lib/tests.nix",
        ]), ([], False))

    def test_safety_shell_check_is_change_scoped(self):
        for path, checked in (
            ("operations.sh", ["game-backup-minecraft", "safety-python", "safety-shell"]),
            ("default.nix", ["game-backup-minecraft", "safety-python", "safety-shell"]),
            ("native.py", ["game-backup-minecraft", "parsec-activation", "safety-python", "safety-shell"]),
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([f"assets/safety/shell/{path}"]), (checked, False))
        for path in (
            "assets/safety/shell/test-operations.sh",
            "fixtures/contracts/safety-shell.md",
            "modules/10-foundations/safety-shell-check.nix",
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), (["safety-shell"], False))

    def test_local_docs_add_no_focused_checks(self):
        self.assertEqual(module.selection([
            "docs/adr/0002-invariant-safety.md",
            "assets/safety/shell/README.md",
            "assets/safety/python/README.md",
            "assets/home-layout/README.md",
            "assets/parsec-activation/README.md",
            "modules/50-features/game-servers/_internal/minecraft-backup/README.md",
        ]), ([], False))

    def test_parsec_check_is_scoped_and_follows_its_core_dependency(self):
        for path in (
            "assets/parsec-activation/activate.py",
            "assets/parsec-activation/test_activation.py",
            "modules/50-features/services/parsec.nix",
            "modules/10-foundations/parsec-activation-check.nix",
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), (["parsec-activation"], False))

    def test_migration_rule_owners_are_mapped(self):
        for path in pathlib.Path("modules/50-features").rglob("*.nix"):
            if "local.homeMigration.paths" in path.read_text():
                with self.subTest(path=str(path)):
                    self.assertIn("home-migration", module.selection([str(path)])[0])

    def test_minecraft_backup_check_follows_consumer_and_policy(self):
        for path in (
            "lib/service-layout.nix",
            "modules/10-foundations/game-backup-minecraft-check.nix",
            "modules/50-features/game-servers/_internal/container.nix",
            "modules/50-features/game-servers/_internal/game.sh",
            "modules/50-features/game-servers/_internal/minecraft-backup/operator.sh",
            "modules/50-features/game-servers/_internal/minecraft-backup/default.nix",
            "modules/50-features/game-servers/_internal/minecraft-backup/test.nix",
            "modules/50-features/game-servers/commands.nix",
            "modules/50-features/game-servers/minecraft.nix",
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), (["game-backup-minecraft"], False))
        for path in ("flake.nix", "flake.lock"):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), (sorted(module.OPTIONAL_CHECKS), True))
        for path in (
            "modules/50-features/game-servers/ark.nix",
            "modules/50-features/game-servers/rust.nix",
            "modules/50-features/services/parsec.nix",
        ):
            self.assertNotIn("game-backup-minecraft", module.selection([path])[0])

    def test_unresolvable_base_is_fail_closed(self):
        with (
            patch.object(module.subprocess, "check_output", side_effect=subprocess.CalledProcessError(128, ["git"])),
            patch.object(sys, "argv", ["select-checks.py"]),
            redirect_stdout(StringIO()) as output,
            redirect_stderr(StringIO()) as diagnostic,
        ):
            module.main()
        self.assertEqual(output.getvalue().splitlines(), [
            f".#checks.x86_64-linux.{name}" for name in module.OPTIONAL_CHECKS
        ])
        self.assertIn("testing all focused checks", diagnostic.getvalue())


if __name__ == "__main__":
    unittest.main()
