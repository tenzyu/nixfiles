"""Home Manager's Linux XDG migration. Check is read-only; apply never merges data."""

import argparse
from contextlib import contextmanager
import datetime
import fcntl
import fnmatch
import json
import os
from pathlib import Path
import re
import stat
import sys
import tomllib
import uuid

import safety_operations as safety
from move_boundary import Conflict, MoveBoundary, Unsupported, absolute, identity, mountinfo


def exists(path):
    try:
        path.lstat()
    except (FileNotFoundError, NotADirectoryError):
        return False
    return True


def store_link(path):
    return (path.is_symlink() and os.readlink(path).startswith("/nix/store/")
            and path.resolve().is_relative_to("/nix/store"))


def tree(path, excluded=()):
    # Path.rglob may silently suppress permission errors. An unreadable directory
    # must never be classified as empty/generated and moved out of the way.
    with os.scandir(path) as entries:
        for entry in entries:
            child = Path(entry.path)
            if any(child == root or child.is_relative_to(root) for root in excluded):
                continue
            yield child
            if entry.is_dir(follow_symlinks=False):
                yield from tree(child, excluded)


def generated_tree(path, managed):
    """Recognize the directory skeleton of enabled Home Manager links."""
    members = {leaf for leaf in managed if leaf != path and leaf.is_relative_to(path)}
    ancestors = {parent for leaf in members for parent in leaf.parents if parent.is_relative_to(path)}
    if not members or path.is_symlink() or not path.is_dir():
        return False

    def trusted_directory(directory):
        info = directory.lstat()
        return (stat.S_ISDIR(info.st_mode) and info.st_uid == os.geteuid()
                and stat.S_IMODE(info.st_mode) in (0o700, 0o755)
                and not os.listxattr(directory, follow_symlinks=False))

    links = 0
    if not trusted_directory(path):
        return False
    for child in tree(path):
        if child.is_symlink():
            if child not in members or not store_link(child):
                return False
            target = Path(os.readlink(child))
            if len(target.parts) < 5 or not target.parts[3].endswith("-home-manager-files"):
                return False
            if os.listxattr(child, follow_symlinks=False):
                return False
            links += 1
        elif child not in ancestors or not trusted_directory(child):
            return False
    return links > 0


@contextmanager
def comparison_entry(parent_fd, name):
    # Pin and inspect before opening for reads. A raced replacement with a
    # symlink, FIFO or device must not be followed or opened for I/O.
    entry = os.open(name, os.O_PATH | os.O_NOFOLLOW, dir_fd=parent_fd)
    try:
        info = os.fstat(entry)
        if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            raise Unsupported("comparison does not follow symlinks or read special entries")
        if stat.S_ISREG(info.st_mode) and info.st_nlink != 1:
            raise Unsupported("comparison cannot establish hard-link identity")
        readable = os.open(f"/proc/self/fd/{entry}", os.O_RDONLY | os.O_NOATIME)
        try:
            yield readable, info
            current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
            if current != info or current.st_ctime_ns != info.st_ctime_ns:
                raise Conflict("an entry changed during comparison")
        finally:
            os.close(readable)
    finally:
        os.close(entry)


def compare_entries(boundary, mount, left_parent, right_parent, left, right):
    with (comparison_entry(left_parent, left) as (left_fd, a),
          comparison_entry(right_parent, right) as (right_fd, b)):
        if boundary.mount(left_fd, left) != mount or boundary.mount(right_fd, right) != mount:
            raise Unsupported("comparison crossed a mount boundary")
        if (a.st_mode, a.st_uid, a.st_gid, a.st_mtime_ns) != (b.st_mode, b.st_uid, b.st_gid, b.st_mtime_ns):
            return False
        attrs = sorted(os.listxattr(left_fd))
        if attrs != sorted(os.listxattr(right_fd)) or any(
            os.getxattr(left_fd, key) != os.getxattr(right_fd, key) for key in attrs
        ):
            return False
        if stat.S_ISDIR(a.st_mode):
            names = sorted(os.listdir(left_fd))
            return names == sorted(os.listdir(right_fd)) and all(
                compare_entries(boundary, mount, left_fd, right_fd, name, name) for name in names
            )
        if a.st_size != b.st_size:
            return False
        while True:
            chunk = os.read(left_fd, 65536)
            if chunk != os.read(right_fd, 65536):
                return False
            if not chunk:
                return True


def describe_collision(boundary, source, target, *, compare):
    if not compare:
        return "Both paths contain data"
    try:
        with (boundary.directory(source.parent) as left,
              boundary.directory(target.parent) as right):
            mount = boundary.mount(left, source.parent)
            if compare_entries(boundary, mount, left, right, source.name, target.name):
                return "Apparent match (no writer exclusion); both paths contain data and are preserved"
    except (Conflict, OSError, RecursionError) as error:
        # Do not print tree members, attribute names, contents or exception text.
        # That information may be sensitive and is unnecessary for remediation.
        return f"Both paths contain data; comparison could not establish a match ({type(error).__name__})"
    return "Both paths contain data and differ"


def virtual(path, moves):
    """Read the future layout without making it (e.g. Claude's nested JSON)."""
    for source, target in reversed(moves):
        if path.is_relative_to(target):
            path = source / path.relative_to(target)
        elif path.is_relative_to(source):
            return None
    return path


def present(path):
    return path is not None and exists(path)


def mounts(path):
    for _, device, root, mountpoint, _ in mountinfo(path):
        yield device, root, mountpoint


def busy(patterns, paths=None):
    host_mounts = list(mounts(Path("/proc/self/mountinfo")))
    filesystem_paths = []
    for path in paths or [Path.home()]:
        path = path.resolve()
        device, root, mountpoint = max(
            (mount for mount in host_mounts if path.is_relative_to(mount[2])),
            key=lambda mount: len(mount[2].parts))
        filesystem_paths.append((device, root / path.relative_to(mountpoint)))
    matches = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            names = [(proc / "comm").read_text().strip(),
                     (proc / "exe").resolve().name]
            # Node-hosted CLIs may have 'node' as both comm and executable.
            names += [os.fsdecode(arg) for arg in
                      (proc / "cmdline").read_bytes().split(b"\0")[:3]]
            if any(fnmatch.fnmatch(name.lower(), pattern.lower())
                   for name in names for pattern in patterns):
                # Same-UID rootless containers need not see the host home at all.
                # Compare filesystem roots, not namespace IDs: a bind mount can
                # expose the home at a different path in another mount namespace.
                try:
                    exposed = any(dev == device and
                                  (path.is_relative_to(mount_root)
                                   or mount_root.is_relative_to(path))
                                  for dev, mount_root, _ in mounts(proc / "mountinfo")
                                  for device, path in filesystem_paths)
                except OSError:
                    exposed = True  # Unknown visibility must still block migration.
                if not exposed:
                    continue
                matches.append(proc.name)
        except (OSError, UnicodeError):
            continue
    return matches


def replace_references(text, source, target, home):
    for old in (str(source), "~/" + str(source.relative_to(home)),
                "$HOME/" + str(source.relative_to(home))):
        text = re.sub(re.escape(old) + r"(?=[/\s\"']|$)", lambda _: str(target), text)
    return text


def relocated_absolute(value, rules):
    """Map legacy absolute paths using the most specific migration rule."""
    if not os.path.isabs(value):
        return None
    path = Path(os.path.normpath(value))
    matches = []
    for rule in rules:
        source, target = Path(rule["source"]), Path(rule["target"])
        if source != target and (path == source or path.is_relative_to(source)):
            matches.append((len(source.parts), target / path.relative_to(source)))
    return max(matches, key=lambda item: item[0])[1] if matches else None


def link_repairs(root, destination, manifest, excluded=()):
    """Plan link changes, including resumption after a successful directory rename."""
    actions = []
    for link in tree(root, excluded):
        if not link.is_symlink():
            continue
        original = os.readlink(link)
        relocated = relocated_absolute(original, manifest["rules"])
        if relocated is None:
            continue
        new_link = destination / link.relative_to(root)
        replacement = os.path.relpath(relocated, new_link.parent)
        if original != replacement:
            actions.append({"action": "symlink", "current": str(link), "target": str(new_link),
                            "original": original, "replacement": replacement})
    return actions


def manifest_paths(manifest):
    home, state = absolute(manifest["home"]), absolute(manifest["state"])
    if home.is_relative_to(state):
        raise Unsupported("Migration state must be separate from HOME and its ancestors")
    paths = [(absolute(rule["source"]), absolute(rule["target"])) for rule in manifest["rules"]]
    targets = []
    for (source, target), rule in zip(paths, manifest["rules"]):
        for path in (source, target):
            if path.is_relative_to(state) or state.is_relative_to(path):
                raise Unsupported(f"Migration state overlaps a rule: {path}")
        for value in rule.get("references", []):
            path = Path(value)
            if not path.parts or path.is_absolute() or ".." in path.parts or "\0" in value:
                raise Unsupported("References must be relative files below the migration target")
        if source != target:
            if any(target.is_relative_to(old) or old.is_relative_to(target) for old, _ in paths):
                raise Unsupported(f"Destination overlaps a legacy source: {target}")
            if any(earlier.is_relative_to(target) for earlier in targets):
                raise Unsupported(f"Destination must come before its nested destinations and occur once: {target}")
            targets.append(target)
    return home, state


def future_parent(path, moves):
    """Find a directory that will contain this path after earlier moves."""
    while True:
        actual = virtual(path, moves)
        if present(actual):
            return actual
        path = path.parent


def check_state(boundary, state):
    with boundary.directory(state, nearest=True) as fd:
        boundary.mount(fd, state)
        boundary.writable(fd, state)
        if exists(state):
            info = os.fstat(fd)
            if info.st_uid != boundary.uid or info.st_mode & 0o077:
                raise Unsupported(f"Migration state must be private and owned by the HOME owner: {state}")


def check_reference(actual, dest, source, target, home):
    try:
        text = actual.read_text()
        updated = replace_references(text, source, target, home)
        if updated == text:
            return False
        if dest.suffix == ".json":
            json.loads(updated)
        elif dest.suffix == ".toml":
            tomllib.loads(updated)
    except ValueError:
        # Parsers may include part of the filename's contents in their errors.
        raise Conflict(f"Cannot validate legacy reference file: {actual}") from None
    if actual.is_symlink():
        raise Conflict(f"Fix old-root references in the declarative source: {actual}")
    return True


def plan(manifest, boundary=None, *, activation=False, compare_collisions=False):
    home, state = manifest_paths(manifest)
    boundary = boundary or MoveBoundary()
    moves, actions, patterns = [], [], []
    managed_paths = [absolute(path) for path in manifest.get("managed", [])]
    for rule in manifest["rules"]:
        source, target = Path(rule["source"]), Path(rule["target"])
        owner = rule["owner"]
        if not isinstance(owner, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", owner):
            raise Unsupported("Migration rule requires a valid feature owner")
        if not source.is_relative_to(home) or source == home:
            raise Conflict(f"Source must be below HOME: {source}")
        if source == target:
            continue
        actual_source, actual_target = virtual(source, moves), virtual(target, moves)
        if present(actual_source):
            with boundary.directory(actual_source.parent):
                pass
            source_entry = identity(actual_source.lstat())
            if source_entry[2] not in (stat.S_IFDIR, stat.S_IFREG):
                raise Conflict(f"Unsupported legacy file type: {source}")
            parent = future_parent(target.parent, moves)
            boundary.same_mount(actual_source.parent, parent, source_entry[0])
            boundary.reject_mounts(actual_source)
            backup = None
            if present(actual_target):
                boundary.reject_mounts(actual_target)
                backup_entry = identity(actual_target.lstat())
                if (source_entry[2] != stat.S_IFDIR or backup_entry[2] != stat.S_IFDIR
                        or not generated_tree(actual_target, managed_paths)):
                    detail = describe_collision(boundary, actual_source, actual_target,
                                                compare=compare_collisions)
                    raise Conflict(f"{detail} ({owner}): {source} -> {target}. "
                                   "Preserve both trees and review the collision in the migration runbook.")
                boundary.same_mount(actual_target.parent, state, backup_entry[0])
                backup = backup_entry
            if source_entry[2] == stat.S_IFDIR:
                for link in tree(actual_source, [old for old, _ in moves]):
                    if not link.is_symlink():
                        continue
                    value = os.readlink(link)
                    if value.startswith(str(source) + "/") or value == str(source):
                        if not rule.get("repairAbsoluteLinks", False):
                            raise Conflict(f"Absolute legacy-root symlink requires repair: {link}")
                    if not os.path.isabs(value):
                        # A relative link to another copied member remains valid,
                        # including cargo -> rustup -> /nix/store/... chains.
                        lexical = Path(os.path.abspath(link.parent / value))
                        if lexical.is_relative_to(actual_source):
                            continue
                        old_resolved = (link.parent / value).resolve()
                        new_link = target / link.relative_to(actual_source)
                        new_resolved = (new_link.parent / value).resolve()
                        if not old_resolved.is_relative_to(actual_source) and old_resolved != new_resolved:
                            raise Conflict(f"Relative symlink would change meaning: {link}")
            # HM checks the current layout before writeBoundary. Check files that
            # will appear there after moving, so linkGeneration cannot clobber them.
            for managed in managed_paths:
                if managed.is_relative_to(target):
                    old = actual_source / managed.relative_to(target)
                    if exists(old) and not store_link(old):
                        raise Conflict(f"Legacy file would collide with a managed file ({owner}): "
                                       f"{old} -> {managed}. Review the Home Manager declaration and "
                                       "preserve the legacy file before applying.")
            actions.append({"action": "move", "source": str(source), "target": str(target),
                            "owner": owner, "entry": source_entry, "backup": backup})
            moves.append((source, target))
            patterns.extend(rule.get("processes", []))
            if rule.get("repairAbsoluteLinks", False) and source_entry[2] == stat.S_IFDIR:
                actions.extend({**repair, "owner": owner, "legacy": str(source), "root": str(target)}
                               for repair in link_repairs(actual_source, target, manifest,
                                                          [old for old, _ in moves[:-1]]))
        elif (rule.get("repairAbsoluteLinks", False) and present(actual_target)
              and actual_target.is_dir() and not actual_target.is_symlink()):
            # Diagnose legacy links even if an earlier version already moved the tree.
            with boundary.directory(actual_target):
                pass
            boundary.reject_mounts(actual_target)
            repairs = link_repairs(actual_target, target, manifest)
            actions.extend({**repair, "owner": owner, "legacy": str(source), "root": str(target)}
                           for repair in repairs)
            if repairs:
                patterns.extend(rule.get("processes", []))

        # Diagnose residual references even if the directory already moved.
        for relative in rule.get("references", []):
            dest = target / relative
            actual = virtual(dest, moves)
            if not present(actual) or not actual.is_file():
                continue
            with boundary.directory(actual.parent):
                if check_reference(actual, dest, source, target, home):
                    actions.append({"action": "rewrite", "current": str(actual), "target": str(dest),
                                    "legacy": str(source), "root": str(target), "owner": owner})
                    patterns.extend(rule.get("processes", []))
    if moves:
        check_state(boundary, state)
    paths = [Path(rule[key]) for rule in manifest["rules"] for key in ("source", "target")]
    pids = busy(patterns, paths) if patterns and not activation else []
    if pids:
        raise Conflict(f"Close applications before migration (PIDs: {', '.join(pids)})")
    return actions


def write_journal(log, event):
    log.write(json.dumps(event, ensure_ascii=True) + "\n")
    log.flush()
    os.fsync(log.fileno())


def commit_move(boundary, log, source, target, entry, kind, *, managed=()):
    with (boundary.directory(source.parent) as source_fd,
          boundary.directory(target.parent, create=True) as target_fd):
        if not boundary.matches(source_fd, source.parent, target_fd, target.parent, entry[0]):
            raise Unsupported(f"Move parents are no longer on the same mount: {source} -> {target}")
        current = os.stat(source.name, dir_fd=source_fd, follow_symlinks=False)
        if identity(current) != entry:
            raise Conflict(f"Move source changed after planning: {source}")
        if kind == "scaffolding" and not generated_tree(source, managed):
            raise Conflict(f"Destination scaffolding changed after planning: {source}")
        intent = safety.MoveNew(boundary.uid, safety.Leaf(source_fd, source.name),
                                safety.Leaf(target_fd, target.name), entry[2])
        event = {"kind": kind, "source": str(source), "target": str(target),
                 "device": entry[0], "inode": entry[1], "type": entry[2]}
        write_journal(log, {"action": "move-intent", **event})
        safety.execute_move(intent, confirmed=True)
        try:
            write_journal(log, {"action": "move", **event})
        except (OSError, KeyboardInterrupt) as error:
            raise safety.OutcomeUnknown(getattr(error, "errno", None),
                                        f"Rename and parent flushes returned success, but completion logging failed: {target}") from error


def commit_batch(boundary, state, actions, managed):
    name = datetime.datetime.now().strftime("%Y%m%dT%H%M%S-") + uuid.uuid4().hex
    run = state / name
    with boundary.directory(state, create=True) as state_fd:
        os.mkdir(name, mode=0o700, dir_fd=state_fd)
        try:
            os.fsync(state_fd)
            with boundary.directory(run) as run_fd:
                fd = os.open("operations.jsonl", os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                             0o600, dir_fd=run_fd)
                with os.fdopen(fd, "w", encoding="utf-8") as log:
                    os.fsync(run_fd)
                    for index, action in enumerate(actions):
                        target = Path(action["target"])
                        if backup := action["backup"]:
                            archive = run / "scaffolding" / str(index)
                            commit_move(boundary, log, target, archive, backup, "scaffolding", managed=managed)
                        commit_move(boundary, log, Path(action["source"]), target, action["entry"], "legacy")
        except (OSError, Conflict, ValueError, KeyboardInterrupt):
            print(f"Inspect source, destination, and backups before retrying. Migration journal: {run}",
                  file=sys.stderr)
            raise
    print(f"Migration journal: {run}")


def apply(manifest):
    home, state = manifest_paths(manifest)
    boundary = MoveBoundary()
    with boundary.directory(home) as home_fd:
        if os.fstat(home_fd).st_uid != boundary.uid:
            raise Unsupported(f"Apply must run as the HOME directory owner: {home}")
        boundary.mount(home_fd, home)
        # An existing, stable inode coordinates cooperating runs without
        # creating state before preflight, even if there is nothing to move.
        try:
            fcntl.flock(home_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Conflict(f"Another migration holds the HOME lock: {home}") from error
        actions = plan(manifest, boundary)
        replacements = [action for action in actions if action["action"] != "move"]
        if replacements:
            paths = ", ".join(action["current"] for action in replacements)
            raise Unsupported(f"Replacement requires exclusive ownership; batch refused: {paths}. "
                              "Run check for the repair proposal and see the Home migration runbook.")
        if actions:
            commit_batch(boundary, state, actions, [Path(path) for path in manifest.get("managed", [])])
    return actions


def display_actions(actions):
    for action in actions:
        if action["action"] == "move":
            backup = action["backup"]
            action = {key: value for key, value in action.items() if key not in ("entry", "backup")}
            if backup:
                action["backup"] = "scaffolding"
        yield action


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("mode", choices=["check", "apply"], nargs="?", default="check")
    checks = parser.add_mutually_exclusive_group()
    checks.add_argument("--require-noop", action="store_true",
                        help="fail read-only check when any migration action is pending")
    checks.add_argument("--activation", action="store_true",
                        help="warn about pending actions; fail on unsafe plans")
    args = parser.parse_args()
    if (args.require_noop or args.activation) and args.mode != "check":
        parser.error("--require-noop and --activation are only valid with check")
    try:
        manifest = json.loads(args.manifest.read_text())
        actions = (apply(manifest) if args.mode == "apply" else
                   plan(manifest, activation=args.activation, compare_collisions=not args.activation))
    except (Conflict, OSError, ValueError, KeyError, TypeError) as error:
        print(f"home migration stopped ({type(error).__name__}): {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("home migration interrupted", file=sys.stderr)
        return 130
    if args.activation:
        for action in actions:
            operation = action["action"]
            current = action.get("current", action.get("source"))
            source = json.dumps(current)
            target = json.dumps(action["target"])
            advice = ("review home-layout-migrate check, back up data and stop its writers before manual apply"
                      if operation == "move" else
                      "run home-layout-migrate check and review the manual repair in the migration runbook")
            if action.get("backup"):
                operation += " (preserves generated scaffolding in migration state)"
            if operation in ("symlink", "rewrite"):
                advice += f" (migration {json.dumps(action['legacy'])} -> {json.dumps(action['root'])})"
            print(f"Warning: home migration pending [{action['owner']}] {operation}: "
                  f"{source} -> {target}; {advice}.", file=sys.stderr)
        return 0
    print(json.dumps(list(display_actions(actions)), ensure_ascii=False, indent=2))
    replacements = any(action["action"] != "move" for action in actions)
    if replacements:
        print("home migration needs operator review: the plan contains existing entries requiring "
              "repair; apply will refuse this batch. See the Home migration runbook.", file=sys.stderr)
    if args.require_noop and actions:
        message = "home migration pending: activation blocked before writes"
        if not replacements:
            message += "; review the plan and explicitly authorize a separate manual apply"
        print(message, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
