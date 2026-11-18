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

    def test_migration_rule_owners_are_mapped(self):
        for path in pathlib.Path("modules").rglob("*.nix"):
            if "local.homeMigration.paths" in path.read_text():
                with self.subTest(path=str(path)):
                    self.assertIn("home-migration", module.selection([str(path)])[0])

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
