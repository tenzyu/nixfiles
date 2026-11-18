#!/usr/bin/env python3
"""Regression tests for the selective CI contract."""

import importlib.util
import pathlib
import unittest

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

    def test_lock_update_checks_dependency_sensitive_modules(self):
        self.assertEqual(module.selection(["flake.lock"]), (sorted(module.OPTIONAL_CHECKS), True))

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


if __name__ == "__main__":
    unittest.main()
