#!/usr/bin/env python3
"""Conservative GC-root audit and guided Nix store maintenance.

No command bypasses GC liveness. Review of current-user-owned `result`
symlinks is advisory; ordinary Nix GC performs store deletion.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Callable

SYSTEM_PROFILE = Path('/nix/var/nix/profiles/system')
CURRENT_SYSTEM = Path('/run/current-system')
BOOTED_SYSTEM = Path('/run/booted-system')
ROOT_SEPARATOR = ' -> '
STORE_PREFIX = '/nix/store/'
RESULT_NAME = re.compile(r'^result(?:-[0-9]+)?$')


class SafetyError(Exception):
    pass


@dataclass(frozen=True)
class Root:
    path: str
    target: str
    category: str
    reason: str


def categorise_root(path: str) -> tuple[str, str]:
    """Classification is advisory, never authorization to unlink."""
    if path.startswith('/nix/var/nix/profiles/system') or path in ('/run/booted-system', '/run/current-system'):
        return 'system', 'NixOS boot/current/system profile; preserve'
    if path.startswith('/run/') or path.startswith('/proc/'):
        return 'runtime', 'running system/process; preserve'
    if ('home-manager' in path or '/home-manager/' in path or
            path.endswith('/.nix-profile') or '/nix/var/nix/profiles/' in path or
            '/nix/var/nix/gcroots/per-user/' in path):
        return 'profile', 'managed profile or Home Manager; preserve'
    if '/.direnv/' in path or path.endswith('/.direnv') or '/nix-direnv/' in path:
        return 'direnv', 'development shell cache; review separately'
    if RESULT_NAME.fullmatch(Path(path).name):
        return 'build-result', 'potential user build result; manual review only'
    return 'other', 'unclassified; leave untouched'


def parse_roots(stdout: str) -> tuple[list[Root], list[str]]:
    roots: list[Root] = []
    unknown: list[str] = []
    for line in stdout.splitlines():
        if not line.strip():
            continue
        if ROOT_SEPARATOR not in line:
            unknown.append(line)
            continue
        path, target = line.rsplit(ROOT_SEPARATOR, 1)
        if not path.startswith('/') or not target.startswith(STORE_PREFIX):
            unknown.append(line)
            continue
        category, reason = categorise_root(path)
        roots.append(Root(path, target, category, reason))
    return roots, unknown


def run_command(*argv: str, capture: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(argv, text=True, check=True, capture_output=capture)
    except FileNotFoundError as e:
        raise SafetyError(f'missing executable: {argv[0]}') from e
    except subprocess.CalledProcessError as e:
        detail = (e.stderr or e.stdout or '').strip() if capture else ''
        raise SafetyError(f'command failed ({e.returncode}): {" ".join(argv)}\n{detail}') from e


def resolve_registered(path: Path) -> str:
    if not path.exists():
        raise SafetyError(f'required system link does not exist: {path}')
    target = str(path.resolve(strict=True))
    if not target.startswith(STORE_PREFIX):
        raise SafetyError(f'expected store path for {path}, got {target}')
    try:
        subprocess.run(
            ['nix-store', '--query', '--requisites', target],
            text=True, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        raise SafetyError(f'cannot verify store closure for {path}: {e}') from e
    return target


def system_state() -> dict[str, str | None]:
    result: dict[str, str | None] = {}
    for key, path in [('current', CURRENT_SYSTEM), ('booted', BOOTED_SYSTEM), ('profile', SYSTEM_PROFILE)]:
        try:
            result[key] = resolve_registered(path)
        except SafetyError as e:
            result[key] = None
            result[key + '_error'] = str(e)
    return result


def system_status_ok(state: dict[str, str | None]) -> bool:
    return all(state.get(k) for k in ('current', 'booted', 'profile'))


def require_safe_generations() -> dict[str, str | None]:
    if os.geteuid() != 0:
        raise SafetyError('system generation pruning requires root')
    state = system_state()
    if not system_status_ok(state):
        raise SafetyError(f'incomplete or unregistered NixOS system: {state}')
    if len({state['current'], state['booted'], state['profile']}) != 1:
        raise SafetyError('booted/current/system profile differ; do not prune until successfully rebooted into the registered system')
    return state


def audit() -> dict:
    state = system_state()
    roots, unknown = parse_roots(run_command('nix-store', '--gc', '--print-roots').stdout)
    dead = [line for line in run_command('nix-store', '--gc', '--print-dead').stdout.splitlines() if line.startswith(STORE_PREFIX)]
    try:
        st = os.statvfs('/nix/store')
        free = st.f_bavail * st.f_frsize
    except OSError:
        free = None
    return {
        'schema_version': 1,
        'system': state,
        'system_valid': system_status_ok(state),
        'free_bytes': free,
        'gc_dead_paths': len(dead),
        'gc_root_counts': dict(sorted(Counter(r.category for r in roots).items())),
        'roots': [asdict(root) for root in roots],
        'unparsed_roots': unknown,
        'notes': [
            'Root category is a heuristic, not proof that it is safe to remove.',
            'Root sizes and GC-dead counts do not predict filesystem bytes freed due to sharing and hard links.',
            'The audit is a point-in-time snapshot; deletion performs fresh checks.',
            'No --ignore-liveness operation is supported.',
        ],
    }


def pretty_audit(report: dict, *, max_roots: int = 30) -> None:
    print('Nix Store Safety Console — read-only audit')
    print('  Current:', report['system'].get('current') or '(missing / unregistered)')
    print('  Booted: ', report['system'].get('booted') or '(missing / unregistered)')
    print('  Profile:', report['system'].get('profile') or '(missing / unregistered)')
    print('  System references:', 'OK' if report['system_valid'] else 'CHECK REQUIRED — destructive operations blocked')
    if report['free_bytes'] is not None:
        print(f"  Filesystem available: {report['free_bytes'] / (1024 ** 3):.2f} GiB")
    print(f"  Currently GC-dead store paths: {report['gc_dead_paths']}")
    print('  GC root categories:')
    for category, count in report['gc_root_counts'].items():
        print(f'    {category:14} {count}')
    roots = report['roots']
    review = [r for r in roots if r['category'] in ('build-result', 'direnv', 'other')]
    if review:
        print(f'  Review hints ({min(len(review), max_roots)}/{len(review)}; not deletion recommendations):')
        for r in review[:max_roots]:
            print(f"    [{r['category']}] {r['path']} -> {r['target']}")
    if report['unparsed_roots']:
        print(f"  Unparsed root lines: {len(report['unparsed_roots'])}; preserved (use audit --json)")
    print('  No system/profile/direnv root is automatically removed.')


def is_under_home(path: Path, home: Path) -> bool:
    """Check lexical path first, then resolved parent to reject symlink escapes."""
    if not path.is_absolute() or not home.is_absolute():
        return False
    try:
        rel = path.relative_to(home)
    except ValueError:
        return False
    if not rel.parts or any(part == '..' for part in rel.parts):
        return False
    try:
        path.parent.resolve(strict=True).relative_to(home.resolve(strict=True))
    except (OSError, ValueError):
        return False
    return True


def eligible_result(root: Root, *, home: Path, uid: int) -> bool:
    """Identify user-owned project result symlinks for display only."""
    path = Path(root.path)
    if root.category != 'build-result' or not is_under_home(path, home):
        return False
    # Exclude hidden XDG/application state and dot-directories from the review.
    if any(part.startswith('.') for part in path.relative_to(home).parts[:-1]):
        return False
    try:
        meta = path.lstat()
        if not stat.S_ISLNK(meta.st_mode) or meta.st_uid != uid:
            return False
        if not root.target.startswith(STORE_PREFIX) or str(path.resolve(strict=True)) != root.target:
            return False
    except OSError:
        return False
    return True


def get_result_roots(*, home: Path | None = None, uid: int | None = None) -> list[Root]:
    if os.geteuid() == 0:
        raise SafetyError('review-results must run as the normal user, without sudo')
    home = home or Path.home()
    uid = os.getuid() if uid is None else uid
    roots, _ = parse_roots(run_command('nix-store', '--gc', '--print-roots').stdout)
    return sorted((r for r in roots if eligible_result(r, home=home, uid=uid)), key=lambda r: r.path)


def input_choice(prompt: str) -> str:
    try:
        return input(prompt).strip()
    except (EOFError, KeyboardInterrupt):
        print('\nCancelled.')
        return ''


def review_results(*, ask: Callable[[str], str] = input_choice) -> int:
    if not sys.stdin.isatty():
        raise SafetyError('review-results is interactive only (requires a terminal)')
    roots = get_result_roots()
    if not roots:
        print('No eligible user-owned result symlinks. direnv/profile roots remain untouched.')
        return 0
    print('User-owned build result links (read-only snapshot, not removal recommendations):')
    for i, r in enumerate(roots, 1):
        print(f'  {i:>3}. {r.path!r}\n       -> {r.target!r}')
    selected = ask('Numbers to review (e.g. 1,3) or Enter to cancel: ')
    if not selected:
        return 0
    if not re.fullmatch(r'\d+(?:\s*,\s*\d+)*', selected):
        raise SafetyError('invalid selection; expected comma-separated item numbers')
    indexes = sorted(set(int(n) for n in selected.split(',')))
    if not indexes or any(n < 1 or n > len(roots) for n in indexes):
        raise SafetyError('selection out of range')
    print('Selected symlinks (advisory only):')
    for i in indexes:
        r = roots[i-1]
        print(f'  Link: {r.path!r} -> {r.target!r}')
    print('Builds can change these links after inspection. Nothing was changed.')
    return 0


def native_gc(*, confirmed: bool) -> None:
    if os.geteuid() != 0:
        raise SafetyError('store GC requires root for this workflow')
    if not confirmed:
        raise SafetyError('gc requires --yes (or confirmation in interactive mode)')
    if not system_status_ok(system_state()):
        raise SafetyError('system references missing: GC cancelled; recover/rebuild the system first')
    print('Running normal Nix GC, with every live GC root respected.', flush=True)
    run_command('nix-store', '--gc', capture=False)


def prune_system(*, keep: int, confirmed: bool) -> None:
    if not 2 <= keep <= 100:
        raise SafetyError('keep must be between 2 and 100; at least 2 generations are required')
    if not confirmed:
        raise SafetyError('prune-system requires --yes (or interactive confirmation)')
    before = require_safe_generations()
    print(f'Keeping at least {keep} recent system generations and newer-than-current generations.')
    run_command('nix-env', '--profile', str(SYSTEM_PROFILE), '--list-generations', capture=False)
    print('Nix profile deletion preview:')
    run_command('nix-env', '--profile', str(SYSTEM_PROFILE), '--delete-generations', f'+{keep}', '--dry-run', capture=False)
    # Revalidate immediately before profile modification; fail closed on pending boot.
    if require_safe_generations() != before:
        raise SafetyError('system changed while preparing generation cleanup; nothing deleted')
    run_command('nix-env', '--profile', str(SYSTEM_PROFILE), '--delete-generations', f'+{keep}', capture=False)
    if not system_status_ok(system_state()):
        raise SafetyError('system references changed or missing after pruning; GC was NOT run')
    print('Generation pruning complete. GC was not run and requires separate confirmation.')


def interactive() -> None:
    report = audit()
    pretty_audit(report)
    while True:
        print('\nActions (all deletion requires separate confirmation):')
        print('  1. Refresh read-only audit')
        print('  2. Review own build result symlinks (read-only; no sudo)')
        print('  3. Native garbage collection (sudo)')
        print('  4. Prune system generations, keep 3 (sudo; requires rebooted/current/profile match)')
        print('  0. Exit')
        choice = input_choice('Select [0-4]: ')
        if choice in ('', '0'):
            return
        try:
            if choice == '1':
                pretty_audit(audit())
            elif choice == '2':
                review_results()
            elif choice == '3':
                if input_choice('Type GC to run Nix garbage collection: ') == 'GC':
                    native_gc(confirmed=True)
            elif choice == '4':
                if input_choice('Type PRUNE to remove old system rollback generations: ') == 'PRUNE':
                    prune_system(keep=3, confirmed=True)
            else:
                print('Invalid choice.')
        except SafetyError as e:
            print(f'Blocked: {e}', file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Safe root audit and interactive Nix GC (never bypasses liveness).')
    parser.add_argument('command', nargs='?', choices=['audit', 'gc', 'prune-system', 'review-results'],
                        default=None, help='review-results lists eligible symlinks without changing them')
    parser.add_argument('--json', action='store_true', help='machine-readable read-only audit')
    parser.add_argument('--yes', action='store_true', help='acknowledge the specified gc/prune-system operation')
    parser.add_argument('--keep-generations', type=int, default=3, metavar='N')
    parser.add_argument('--dry-run', action='store_true', help='alias for read-only audit')
    args = parser.parse_args(argv)
    command = 'audit' if args.dry_run else args.command
    if args.json and command not in (None, 'audit'):
        parser.error('--json is only valid for audit')
    if command is None:
        command = 'interactive' if sys.stdin.isatty() and sys.stdout.isatty() else 'audit'
    try:
        if command == 'interactive':
            interactive()
        elif command == 'audit':
            report = audit()
            if args.json:
                print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
            else:
                pretty_audit(report)
        elif command == 'gc':
            native_gc(confirmed=args.yes)
        elif command == 'prune-system':
            prune_system(keep=args.keep_generations, confirmed=args.yes)
        elif command == 'review-results':
            review_results()
        return 0
    except SafetyError as e:
        print(f'ERROR: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
