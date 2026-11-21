#!/usr/bin/env python3
"""Regression tests for selective CI, including the workflow's Git inputs."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name("select-checks.py")
spec = importlib.util.spec_from_file_location("select_checks", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

ALL = module.Selection(module.OPTIONAL_CHECKS, True, True)
BASELINE = module.Selection([], False, False)


class SelectionTests(unittest.TestCase):
    def test_documentation_and_framework_fixtures_are_baseline_only(self):
        self.assertEqual(module.selection([
            "README.md",
            "docs/index.md",
            "docs/memory/provenance.json",
            "assets/safety/shell/README.md",
            "scripts/osu-performance/README-lab.md",
            "modules/_internal/configurations/tests/trace.nix",
            "lib/tests.nix",
        ]), BASELINE)

    def test_known_components_stay_focused(self):
        for path, checks in (
            ("assets/home-authority/test-vm.py", ["home-authority-vm"]),
            ("assets/home-authority/seal-acceptance.py", ["home-authority-seal-vm", "home-authority-vm"]),
            ("modules/50-features/home/home-authority-seal-vm.nix", ["home-authority-seal-vm", "home-migration"]),
            ("modules/50-features/home/home-authority-vm.nix", ["home-authority-vm", "home-migration"]),
            ("modules/50-features/home/home-authority.nix", ["home-authority-vm", "home-migration"]),
            ("assets/home-layout/migrate.py", ["home-migration"]),
            ("assets/home-layout/test-activation.sh", ["home-migration"]),
            ("modules/50-features/home/home-migration.nix", ["home-migration"]),
            ("assets/nix-store-clean/cli.py", ["nix-store-clean"]),
            ("modules/50-features/nix/nix-store-clean.nix", ["home-migration", "nix-store-clean"]),
            ("assets/opencode/direnv.ts", ["opencode-direnv"]),
            ("modules/50-features/development/rtk.nix", ["home-migration", "rtk-rewrites"]),
            ("assets/steam-gaming/test-launch.sh", ["steam-gaming"]),
            ("modules/50-features/gaming/steam.nix", ["home-migration", "steam-gaming"]),
            ("assets/parsec-activation/activate.py", ["parsec-activation"]),
            ("modules/50-features/services/parsec.nix", ["home-migration", "parsec-activation"]),
            ("modules/10-foundations/game-backup-minecraft-check.nix", ["game-backup-minecraft"]),
            ("modules/50-features/game-servers/_internal/minecraft-backup/writer.sh", ["game-backup-minecraft"]),
            ("modules/50-features/game-servers/minecraft.nix", ["game-backup-minecraft", "home-migration"]),
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), module.Selection(checks, False, False))

    def test_interoperability_and_contract_dependencies(self):
        for path, checks in (
            ("assets/safety/python/test_operations.py", ["safety-python"]),
            ("assets/safety/python/default.nix", ["home-migration", "safety-python"]),
            ("assets/safety/python/safety_operations.py", ["home-migration", "safety-python"]),
            ("assets/safety/shell/operations.sh", ["game-backup-minecraft", "safety-python", "safety-shell"]),
            ("assets/safety/shell/default.nix", ["game-backup-minecraft", "safety-python", "safety-shell"]),
            ("assets/safety/shell/native.py", ["game-backup-minecraft", "parsec-activation", "safety-python", "safety-shell"]),
            ("assets/safety/shell/test-operations.sh", ["safety-shell"]),
            ("fixtures/contracts/safety-shell.md", ["safety-shell"]),
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), module.Selection(checks, False, False))

    def test_lab_and_cache_inputs(self):
        for path in ("osu-lab.py", "test-osu-lab.py"):
            self.assertEqual(
                module.selection([f"scripts/osu-performance/{path}"]),
                module.Selection([], False, True),
            )
        self.assertEqual(
            module.selection(["modules/50-features/gaming/neko5-osu-first.nix"]),
            module.Selection(["home-migration"], False, True),
        )
        self.assertEqual(
            module.selection(["modules/50-features/media/_internal/cache.nix"]),
            module.Selection(["home-migration"], True, False),
        )
        self.assertEqual(
            module.selection(["scripts/ci/audit-splitcast-cache.sh"]),
            module.Selection([], True, False),
        )

    def test_unclassified_and_shared_inputs_widen(self):
        for path in (
            "modules/50-features/hardware/new/default.nix",
            "modules/50-features/media/splitcast-production.nix",
            "modules/50-features/nix/nix.nix",
            "modules/50-features/game-servers/_internal/container.nix",
            "modules/50-features/game-servers/_internal/game.sh",
            "lib/service-layout.nix",
            "lib/features.nix",
            "assets/safety/python/new-helper.py",
            "fixtures/contracts/novel.md",
            "scripts/new-command",
            "scripts/ci/select-checks.py",
            "scripts/ci/test_select_checks.py",
            ".github/workflows/nix-validation.yml",
            "modules/10-foundations/overlays.nix",
            "modules/00-hosts/neko5/configuration.nix",
            "modules/_internal/configurations/lib/seed.nix",
            "flake.lock",
            "flake.nix",
        ):
            with self.subTest(path=path):
                self.assertEqual(module.selection([path]), ALL)

    def test_diagnostics_distinguish_known_consumers_from_fallback(self):
        reasons = []
        module.selection(["modules/50-features/hardware/new/default.nix"], explain=reasons.append)
        self.assertEqual(len(reasons), 1)
        self.assertIn("all focused targets (known consumers: home-migration)", reasons[0])

    def test_deduplication_and_order(self):
        self.assertEqual(module.selection([
            "assets/rtk/test_rewrites.py",
            "assets/steam-gaming/test-launch.sh",
            "assets/opencode/direnv.ts",
            "assets/opencode/direnv.test.ts",
        ]), module.Selection(["opencode-direnv", "rtk-rewrites", "steam-gaming"], False, False))


class GitDiffTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.repo = Path(scratch.name) / "repo"
        self.env = os.environ.copy()
        self.env.pop("NIX_CHECK_BASE", None)
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Selector fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.write("README.md", "ordinary docs")
        self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env, text=True).strip()

    def write(self, path, content="fixture"):
        file = self.repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "-qm", "fixture commit")
        return self.git("rev-parse", "HEAD")

    def selector(self, *args):
        return subprocess.run(
            [sys.executable, SCRIPT, *args],
            cwd=self.repo, env=self.env, check=True, capture_output=True, text=True,
        )

    def assert_outputs(self, result, expected):
        self.assertEqual(result.stdout.splitlines(), [
            "checks=" + " ".join(f".#checks.x86_64-linux.{check}" for check in expected.checks),
            "cache_probe=" + ("yes" if expected.cache_probe else "no"),
            "osu_lab=" + ("yes" if expected.osu_lab else "no"),
        ])

    def test_pr_synthetic_merge_uses_only_changes_from_first_parent(self):
        self.git("checkout", "-qb", "pr")
        self.write("assets/rtk/test_rewrites.py")
        self.commit()
        self.git("checkout", "-q", "main")
        self.write("scripts/base-only.py")
        base = self.commit()
        self.git("merge", "-q", "--no-ff", "-m", "synthetic PR merge", "pr")
        self.assertEqual(self.git("rev-parse", "HEAD^1"), base)

        result = self.selector("--github-output")
        self.assert_outputs(result, module.Selection(["rtk-rewrites"], False, False))
        self.assertIn("'assets/rtk/test_rewrites.py': rtk-rewrites", result.stderr)
        self.assertNotIn("base-only", result.stderr)

    def test_multi_commit_push_uses_event_before_sha(self):
        self.env["NIX_CHECK_BASE"] = self.git("rev-parse", "HEAD")
        self.write("assets/home-layout/migrate.py")
        self.commit()
        self.write("scripts/osu-performance/osu-lab.py")
        self.commit()

        result = self.selector("--github-output")
        self.assert_outputs(result, module.Selection(["home-migration"], False, True))
        self.assertEqual(self.selector().stdout, ".#checks.x86_64-linux.home-migration\n")
        self.assertEqual(self.selector("--cache-only").stdout, "no\n")

    def test_missing_and_shallow_bases_run_all_focused_targets(self):
        self.env["NIX_CHECK_BASE"] = "0" * 40
        result = self.selector("--github-output")
        self.assert_outputs(result, ALL)
        self.assertIn("cannot resolve diff", result.stderr)
        self.assertEqual(self.selector("--cache-only").stdout, "yes\n")

        self.env["NIX_CHECK_BASE"] = self.git("rev-parse", "HEAD")
        self.write("docs/index.md")
        self.commit()
        clone = self.repo.parent / "shallow"
        self.git("clone", "-q", "--depth", "1", self.repo.as_uri(), str(clone))
        self.repo = clone
        self.assertEqual(self.git("rev-parse", "--is-shallow-repository"), "true")
        self.assert_outputs(self.selector("--github-output"), ALL)
        self.env.pop("NIX_CHECK_BASE")
        self.assert_outputs(self.selector("--github-output"), ALL)

    def test_rename_and_deletion_preserve_both_paths_and_odd_names(self):
        self.git("config", "diff.renames", "true")
        old = os.fsdecode(b"assets/home-layout/old \n\xff.py")
        new = "assets/opencode/-new\tname.ts"
        removed = "fixtures/contracts/safety-shell.md"
        self.write(old)
        self.write(removed)
        self.commit()
        (self.repo / new).parent.mkdir()
        (self.repo / old).rename(self.repo / new)
        (self.repo / removed).unlink()
        self.commit()

        result = self.selector("--github-output")
        self.assert_outputs(result, module.Selection(["home-migration", "opencode-direnv", "safety-shell"], False, False))
        for path in (old, new, removed):
            self.assertIn(f"{path!r}:", result.stderr)

    def test_ordinary_docs_and_executable_markdown(self):
        self.write("docs/ordinary.md")
        self.commit()
        result = self.selector("--github-output")
        self.assert_outputs(result, BASELINE)
        self.assertEqual(self.selector().stdout, "")
        self.assertIn("documentation; always-on gates", result.stderr)

        (self.repo / "docs/ordinary.md").chmod(0o755)
        self.commit()
        result = self.selector("--github-output")
        self.assert_outputs(result, ALL)
        self.assertIn("executable or non-regular documentation path", result.stderr)

    def test_new_migration_rule_without_selector_registration(self):
        path = "modules/50-features/hardware/novel-migration.nix"
        self.write(path, """
{
  flake.modules.homeManager.novel-migration = {
    local.homeMigration.paths = [{ source = "legacy"; target = "current"; }];
  };
}
""")
        self.commit()
        result = self.selector("--github-output")
        self.assert_outputs(result, ALL)
        self.assertIn(f"{path!r}: unclassified or shared input", result.stderr)
        self.assertIn("known consumers: home-migration", result.stderr)


if __name__ == "__main__":
    unittest.main()
