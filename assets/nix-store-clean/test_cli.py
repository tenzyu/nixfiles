"""No Nix daemon or privileged NixOS VM required for these deterministic tests."""
import importlib.util
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location('nix_store_clean', Path(__file__).with_name('cli.py'))
import sys
MOD = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MOD
SPEC.loader.exec_module(MOD)


class ClassificationTests(unittest.TestCase):
    def test_critical_roots_never_classified_as_results(self):
        for p in ('/run/current-system', '/run/booted-system',
                  '/nix/var/nix/profiles/system-47-link',
                  '/nix/var/nix/profiles/per-user/root/profile-1-link',
                  '/home/tenzyu/.local/state/home-manager/gcroots/current-home'):
            self.assertNotEqual(MOD.categorise_root(p)[0], 'build-result', p)

    def test_parse_and_preserve_unknown(self):
        parsed, unknown = MOD.parse_roots('''/home/tenzyu/repo/result -> /nix/store/abc-hello
/run/booted-system -> /nix/store/def-system
skipping invalid root
/wrong/root -> /tmp/whatever
''')
        self.assertEqual([r.category for r in parsed], ['build-result', 'system'])
        self.assertEqual(len(unknown), 2)

    def test_direnv_is_not_a_build_result(self):
        self.assertEqual(MOD.categorise_root('/home/user/repo/.direnv/gcroots/shell')[0], 'direnv')

    def test_legacy_destructive_flags_fail_closed(self):
        for args in (['--delete', '--yes'], ['--allow-booted-diff'], ['--root', '/nix/store/example']):
            with self.subTest(args=args), self.assertRaises(SystemExit) as caught:
                MOD.main(args)
            self.assertEqual(caught.exception.code, 2)


class ResultSymlinkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.home.mkdir()
        self.store = self.base / 'nix' / 'store'
        self.store.mkdir(parents=True)
        self.output = self.store / 'abc-output'
        self.output.mkdir()
        self.link = self.home / 'repo' / 'result'
        self.link.parent.mkdir()
        self.link.symlink_to(self.output)
        self.root = MOD.Root(str(self.link), str(self.output), 'build-result', 'manually review')
        store_patch = mock.patch.object(MOD, 'STORE_PREFIX', str(self.store) + '/')
        store_patch.start()
        self.addCleanup(store_patch.stop)

    def test_user_owned_result_link_is_selectable(self):
        self.assertTrue(MOD.eligible_result(self.root, home=self.home, uid=os.getuid()))

    def test_regular_file_and_wrong_uid_not_selectable(self):
        self.assertFalse(MOD.eligible_result(self.root, home=self.home, uid=os.getuid()+1))
        self.link.unlink()
        self.link.write_text('not a symlink')
        self.assertFalse(MOD.eligible_result(self.root, home=self.home, uid=os.getuid()))

    def test_link_escape_and_changed_target_not_selectable(self):
        other = self.base / 'outside' / 'result'
        other.parent.mkdir()
        other.symlink_to(self.output)
        escaped = MOD.Root(str(other), str(self.output), 'build-result', 'manual')
        self.assertFalse(MOD.eligible_result(escaped, home=self.home, uid=os.getuid()))
        self.assertFalse(MOD.eligible_result(MOD.Root(str(self.link), '/nix/store/different', 'build-result', 'manual'), home=self.home, uid=os.getuid()))

    def test_hidden_state_result_is_not_actionable(self):
        hidden = self.home / '.local' / 'state' / 'whatever' / 'result'
        hidden.parent.mkdir(parents=True)
        hidden.symlink_to(self.output)
        r = MOD.Root(str(hidden), str(self.output), 'build-result', '')
        self.assertFalse(MOD.eligible_result(r, home=self.home, uid=os.getuid()))

    def test_root_type_check(self):
        self.assertFalse(MOD.eligible_result(MOD.Root(str(self.link), str(self.output), 'profile', 'preserve'), home=self.home, uid=os.getuid()))

    def test_symlink_parent_escape(self):
        linkdir = self.home / 'redirect'
        linkdir.symlink_to(self.base / 'outside')
        (self.base / 'outside').mkdir()
        other = linkdir / 'result'
        other.symlink_to(self.output)
        self.assertFalse(MOD.eligible_result(MOD.Root(str(other), str(self.output), 'build-result', ''), home=self.home, uid=os.getuid()))

    def test_review_is_sorted_read_only_and_never_reads_stdin(self):
        unusual = self.home / " a 'quoted' \x1b -> project" / 'result-2'
        unusual.parent.mkdir()
        unusual.symlink_to(self.output)
        hidden = self.home / '.direnv' / 'result'
        hidden.parent.mkdir()
        hidden.symlink_to(self.output)
        roots = [self.link, hidden, unusual]
        fake = subprocess.CompletedProcess([], 0, stdout=''.join(f'{p} -> {self.output}\n' for p in roots))
        before = self.link.lstat()
        for isatty in (False, True):
            with self.subTest(isatty=isatty), \
                 mock.patch.object(MOD.subprocess, 'run', return_value=fake) as run, \
                 mock.patch.object(MOD.Path, 'home', return_value=self.home), \
                 mock.patch.object(MOD.os, 'geteuid', return_value=1000), \
                 mock.patch.object(MOD.sys, 'stdin') as stdin, \
                 mock.patch('builtins.input', side_effect=AssertionError('unexpected prompt')), \
                 redirect_stdout(StringIO()) as output:
                stdin.isatty.return_value = isatty
                output.isatty = lambda: isatty
                self.assertEqual(MOD.main(['review-results', '--yes']), 0)
            self.assertEqual(stdin.mock_calls, [])
            run.assert_called_once_with(('nix-store', '--gc', '--print-roots'),
                                        text=True, check=True, capture_output=True)
            report = output.getvalue()
            observed = f'  Observed target: {str(self.output)!r}'
            self.assertEqual([line for line in report.splitlines() if line.startswith('  ')], [
                f'  Link: {str(unusual)!r}', observed, f'  Link: {str(self.link)!r}', observed,
            ])
            self.assertNotIn('\x1b', report)
            self.assertIn('readlink -e', report)
            self.assertIn('check whether the project still needs that output', report)
            self.assertIn('nix-store --gc --print-roots', report)
        self.assertEqual(self.link.lstat().st_ino, before.st_ino)
        self.assertEqual(self.link.readlink(), self.output)
        self.assertTrue(self.output.exists())

    def test_review_excludes_links_changed_after_inventory(self):
        gone = self.link.with_name('result-2')
        gone.symlink_to(self.output)
        replacement = self.store / 'replacement'
        replacement.mkdir()

        def inventory(argv, **kwargs):
            output = f'{self.link} -> {self.output}\n{gone} -> {self.output}\n'
            self.link.unlink()
            self.link.symlink_to(replacement)
            gone.unlink()
            return subprocess.CompletedProcess(argv, 0, stdout=output)

        with mock.patch.object(MOD.subprocess, 'run', side_effect=inventory), \
             mock.patch.object(MOD.Path, 'home', return_value=self.home), \
             mock.patch.object(MOD.os, 'geteuid', return_value=1000), \
             redirect_stdout(StringIO()) as output:
            self.assertEqual(MOD.main(['review-results']), 0)
        self.assertIn('No eligible user-owned result symlinks found.', output.getvalue())
        self.assertNotIn('Observed target:', output.getvalue())
        self.assertIn('nix-store --gc --print-roots', output.getvalue())
        self.assertEqual(self.link.readlink(), replacement)
        self.assertFalse(gone.is_symlink())

    def test_review_reports_native_inventory_failure(self):
        failure = subprocess.CalledProcessError(1, ['nix-store'], stderr='inventory unavailable')
        with mock.patch.object(MOD.subprocess, 'run', side_effect=failure), \
             mock.patch.object(MOD.Path, 'home', return_value=self.home), \
             mock.patch.object(MOD.os, 'geteuid', return_value=1000), \
             redirect_stdout(StringIO()) as output, redirect_stderr(StringIO()) as errors:
            self.assertEqual(MOD.main(['review-results']), 1)
        self.assertEqual(output.getvalue(), '')
        self.assertIn('inventory unavailable', errors.getvalue())

    def test_review_refuses_root_before_inventory(self):
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD.subprocess, 'run') as run, redirect_stderr(StringIO()) as errors:
            self.assertEqual(MOD.main(['review-results']), 1)
        run.assert_not_called()
        self.assertIn('without sudo', errors.getvalue())

    def test_menu_review_returns_to_main_menu_without_second_prompt(self):
        with mock.patch.object(MOD, 'audit'), mock.patch.object(MOD, 'pretty_audit'), \
             mock.patch.object(MOD, 'get_result_roots', return_value=[self.root]), \
             mock.patch('builtins.input', side_effect=['2', '0']) as ask, \
             redirect_stdout(StringIO()) as output:
            MOD.interactive()
        self.assertEqual(ask.call_args_list, [mock.call('Select [0-4]: ')] * 2)
        self.assertIn(f'Link: {str(self.link)!r}', output.getvalue())


class DestructiveOperationTests(unittest.TestCase):
    good_system = {'booted': '/nix/store/system-a', 'current': '/nix/store/system-a', 'profile': '/nix/store/system-a'}

    def test_native_gc_never_bypasses_liveness(self):
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD, 'system_state', return_value=self.good_system), \
             mock.patch.object(MOD, 'run_command') as run:
            MOD.native_gc(confirmed=True)
            run.assert_called_once_with('nix-store', '--gc', capture=False)

    def test_no_confirmation_no_mutation(self):
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD, 'run_command') as run:
            with self.assertRaisesRegex(MOD.SafetyError, 'requires --yes'):
                MOD.native_gc(confirmed=False)
            with self.assertRaisesRegex(MOD.SafetyError, 'requires --yes'):
                MOD.prune_system(keep=3, confirmed=False)
            run.assert_not_called()

    def test_gc_requires_valid_system_references(self):
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD, 'system_state', return_value=self.good_system | {'booted': None}), \
             mock.patch.object(MOD, 'run_command') as run:
            with self.assertRaisesRegex(MOD.SafetyError, 'system references missing'):
                MOD.native_gc(confirmed=True)
            run.assert_not_called()

    def test_prune_pending_boot_is_blocked(self):
        pending = self.good_system | {'profile': '/nix/store/system-b'}
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD, 'system_state', return_value=pending), \
             mock.patch.object(MOD, 'run_command') as run:
            with self.assertRaises(MOD.SafetyError):
                MOD.prune_system(keep=3, confirmed=True)
            run.assert_not_called()

    def test_prune_preserves_at_least_two_generations(self):
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD, 'system_state', return_value=self.good_system), \
             mock.patch.object(MOD, 'run_command') as run:
            with self.assertRaises(MOD.SafetyError):
                MOD.prune_system(keep=1, confirmed=True)
            run.assert_not_called()

    def test_prune_uses_supported_profile_command(self):
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD, 'system_state', return_value=self.good_system), \
             mock.patch.object(MOD, 'run_command') as run:
            MOD.prune_system(keep=3, confirmed=True)
            self.assertEqual(run.call_args_list, [
                mock.call('nix-env', '--profile', str(MOD.SYSTEM_PROFILE), '--list-generations', capture=False),
                mock.call('nix-env', '--profile', str(MOD.SYSTEM_PROFILE), '--delete-generations', '+3', '--dry-run', capture=False),
                mock.call('nix-env', '--profile', str(MOD.SYSTEM_PROFILE), '--delete-generations', '+3', capture=False),
            ])

    def test_prune_refuses_system_change_after_preview(self):
        next_system = dict.fromkeys(self.good_system, '/nix/store/system-b')
        with mock.patch.object(MOD.os, 'geteuid', return_value=0), \
             mock.patch.object(MOD, 'system_state', side_effect=[self.good_system, next_system]), \
             mock.patch.object(MOD, 'run_command') as run:
            with self.assertRaisesRegex(MOD.SafetyError, 'system changed while preparing'):
                MOD.prune_system(keep=3, confirmed=True)
        self.assertEqual(run.call_args_list, [
            mock.call('nix-env', '--profile', str(MOD.SYSTEM_PROFILE), '--list-generations', capture=False),
            mock.call('nix-env', '--profile', str(MOD.SYSTEM_PROFILE), '--delete-generations', '+3', '--dry-run', capture=False),
        ])

    def test_nonroot_fails_closed(self):
        with mock.patch.object(MOD.os, 'geteuid', return_value=1000):
            with self.assertRaises(MOD.SafetyError):
                MOD.prune_system(keep=3, confirmed=True)
            with self.assertRaises(MOD.SafetyError):
                MOD.native_gc(confirmed=True)

    def test_audit_is_read_only(self):
        def fake(*args, **kwargs):
            if args[-1] == '--print-roots':
                out = '/run/current-system -> /nix/store/system-a\n/home/test/result -> /nix/store/output\nunparsed\n'
            elif args[-1] == '--print-dead':
                out = '/nix/store/dead\n'
            else:
                self.fail(f'Unexpected process: {args!r}')
            return subprocess.CompletedProcess(args, 0, stdout=out)
        with mock.patch.object(MOD, 'run_command', side_effect=fake) as run, \
             mock.patch.object(MOD, 'system_state', return_value=self.good_system):
            report = MOD.audit()
        self.assertEqual(report['gc_dead_paths'], 1)
        self.assertEqual(report['gc_root_counts'], {'build-result': 1, 'system': 1})
        self.assertEqual(json.loads(json.dumps(report))['schema_version'], 1)
        self.assertEqual(report['unparsed_roots'], ['unparsed'])
        self.assertEqual(run.call_count, 2)


if __name__ == '__main__':
    unittest.main()
