"""Home Manager's Linux XDG migration. Check is read-only; apply never merges data."""

import argparse
from contextlib import contextmanager
import datetime
import fcntl
import hashlib
import fnmatch
import json
import os
import socket
import subprocess
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
    except FileNotFoundError:
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
            if child not in members or not owned_link(child, managed):
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


def groups(manifest):
    result = {}
    for rule in manifest["rules"]:
        group = rule.get("group", rule["owner"])
        if not re.fullmatch(r"[A-Za-z0-9_-]+", group):
            raise Unsupported("Migration rule requires a valid group")
        result.setdefault(group, []).append(rule)
    return result


def overlaps(first, second):
    return first.is_relative_to(second) or second.is_relative_to(first)


def manifest_paths(manifest):
    home, state = absolute(manifest["home"]), absolute(manifest["state"])
    if home.is_relative_to(state):
        raise Unsupported("Migration state must be separate from HOME and its ancestors")
    paths = [(absolute(rule["source"]), absolute(rule["target"])) for rule in manifest["rules"]]
    targets = []
    entries = list(zip(paths, manifest["rules"]))
    for index, ((source, target), rule) in enumerate(entries):
        group = rule.get("group", rule["owner"])
        for (earlier_source, earlier_target), earlier_rule in entries[:index]:
            earlier_group = earlier_rule.get("group", earlier_rule["owner"])
            if (overlaps(source, earlier_source) or overlaps(target, earlier_target)) and group != earlier_group:
                raise Unsupported(f"Overlapping migration groups: {earlier_group} and {group}")
            if source.is_relative_to(earlier_source):
                raise Unsupported(f"Nested sources must precede their parents and occur once: {source}")
            if group == earlier_group and rule["owner"] != earlier_rule["owner"]:
                raise Unsupported(f"Migration group requires one owner: {group}")
        if not target.is_relative_to(home) and not any(
                target.is_relative_to(absolute(base)) for base in manifest.get("externalBases", [])):
            if manifest.get("version") == 2:
                raise Unsupported(f"External target requires a declared XDG base: {target}")
        for path in (source, target, *protected_roots([rule])):
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
        mount = boundary.mount(fd, state)
        if boundary.mounts[mount][-1] == "tmpfs":
            raise Unsupported(f"Migration journal needs durable storage: {state}")
        boundary.writable(fd, state)
        if exists(state):
            info = os.fstat(fd)
            if info.st_uid != boundary.uid or info.st_mode & 0o077:
                raise Unsupported(f"Migration state must be private and owned by the HOME owner: {state}")


def resolve_external(boundary, manifest, path):
    if path.is_relative_to(absolute(manifest["home"])) or manifest.get("version") != 2:
        return
    bases = [absolute(base) for base in manifest.get("externalBases", []) if path.is_relative_to(base)]
    if not bases:
        raise Unsupported(f"External root requires a declared XDG base: {path}")
    base = max(bases, key=lambda candidate: len(candidate.parts))
    with boundary.directory(base) as fd:
        mount = boundary.mount(fd, base)
    return boundary.mounts[mount][2]


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


def plan(manifest, boundary=None, *, activation=False, compare_collisions=False, generated=None):
    home, state = manifest_paths(manifest)
    boundary = boundary or MoveBoundary()
    moves, actions, patterns = [], [], []
    generated = generated or {}
    managed_paths = set(generated) if generated else set(map(absolute, manifest.get("managed", [])))
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
        source_info = boundary.entry(actual_source) if actual_source is not None else None
        if source_info is not None:
            resolve_external(boundary, manifest, target)
            source_entry = identity(source_info)
            if source_entry[2] not in (stat.S_IFDIR, stat.S_IFREG):
                raise Conflict(f"Unsupported legacy file type: {source}")
            parent = future_parent(target.parent, moves)
            with (boundary.directory(actual_source.parent) as left, boundary.directory(parent) as right):
                source_mount = boundary.mount(left, actual_source.parent)
                target_mount = boundary.mount(right, parent)
                boundary.writable(left, actual_source.parent)
                boundary.writable(right, parent)
            boundary.reject_mounts(actual_source)
            backup = None
            target_info = boundary.entry(actual_target) if actual_target is not None else None
            if target_info is not None:
                boundary.reject_mounts(actual_target)
                backup_entry = identity(target_info)
                if (source_entry[2] != stat.S_IFDIR or backup_entry[2] != stat.S_IFDIR
                        or not generated_tree(actual_target, generated)):
                    detail = describe_collision(boundary, actual_source, actual_target,
                                                compare=compare_collisions)
                    raise Conflict(f"{detail} ({owner}): {source} -> {target}. "
                                   "Preserve both trees and review the collision in the migration runbook.")
                backup = backup_entry
            if source_entry[2] == stat.S_IFDIR:
                for link in tree(actual_source, [old for old, _ in moves]):
                    if not link.is_symlink():
                        continue
                    value = os.readlink(link)
                    if relocated_absolute(value, manifest["rules"]) is not None:
                        if not rule.get("repairAbsoluteLinks", False):
                            raise Conflict(f"Absolute legacy-root symlink requires repair: {link}")
                    if not os.path.isabs(value):
                        # A relative link to another copied member remains valid,
                        # including cargo -> rustup -> /nix/store/... chains.
                        lexical = Path(os.path.abspath(link.parent / value))
                        if lexical.is_relative_to(actual_source):
                            translated = relocated_absolute(str(lexical), manifest["rules"])
                            expected = target / lexical.relative_to(actual_source)
                            if translated is not None and translated != expected:
                                raise Conflict(f"Relative symlink crosses a separately moved root: {link}")
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
                    if exists(old) and not owned_link(old, generated):
                        raise Conflict(f"Legacy file would collide with a managed file ({owner}): "
                                       f"{old} -> {managed}. Review the Home Manager declaration and "
                                       "preserve the legacy file before applying.")
            actions.append({"action": "move", "source": str(source), "target": str(target),
                            "owner": owner, "entry": source_entry, "backup": backup,
                            "sourceMount": source_mount, "targetMount": target_mount})
            moves.append((source, target))
            patterns.extend(rule.get("processes", []))
            if rule.get("repairAbsoluteLinks", False) and source_entry[2] == stat.S_IFDIR:
                actions.extend({**repair, "owner": owner, "legacy": str(source), "root": str(target)}
                               for repair in link_repairs(actual_source, target, manifest,
                                                          [old for old, _ in moves[:-1]]))
        elif (rule.get("repairAbsoluteLinks", False) and actual_target is not None
              and (info := boundary.entry(actual_target)) is not None and stat.S_ISDIR(info.st_mode)):
            # Diagnose legacy links even if an earlier version already moved the tree.
            with boundary.directory(actual_target):
                pass
            boundary.reject_mounts(actual_target)
            repairs = link_repairs(actual_target, target, manifest)
            actions.extend({**repair, "owner": owner, "legacy": str(source), "root": str(target)}
                           for repair in repairs)
            if repairs:
                patterns.extend(rule.get("processes", []))
        elif actual_target is not None and (info := boundary.entry(actual_target)) is not None:
            if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
                raise Conflict(f"Unsafe application root: {target}")

        # Diagnose residual references even if the directory already moved.
        for relative in rule.get("references", []):
            dest = target / relative
            actual = virtual(dest, moves)
            if actual is None or boundary.entry(actual) is None:
                continue
            with boundary.directory(actual.parent):
                if not (actual.is_file() and (not actual.is_symlink() or store_link(actual))):
                    raise Conflict(f"Unknown reference file type: {actual}")
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


def generation_path(value):
    if not value:
        return None
    try:
        path = Path(value).resolve(strict=True)
    except FileNotFoundError:
        return None
    if path.parent != Path("/nix/store") or not path.is_dir():
        raise Unsupported("Expected a realised Home Manager generation in the store")
    return path


def generation_files(home, generation):
    if generation is None:
        return {}
    root = (generation / "home-files").resolve(strict=True)
    if root.parent != Path("/nix/store") or not root.is_dir():
        raise Unsupported("Expected realised Home Manager files in the store")
    return {home / leaf.relative_to(root): {str(leaf)}
            for leaf in tree(root) if leaf.is_symlink() or leaf.is_file()}


def active_generations(home, *state_homes):
    generations = set()
    for base in set(state_homes) - {None} | {str(home / ".local/state")}:
        previous = generation_path(Path(base) / "home-manager/gcroots/current-home")
        if previous:
            generations.add(previous)
    return generations


def merge_generation_files(files, home, generations):
    for generation in generations:
        for path, referents in generation_files(home, generation).items():
            files.setdefault(path, set()).update(referents)


def owned_link(path, generated):
    return store_link(path) and os.readlink(path) in generated.get(path, ())


def protected_roots(rules):
    roots = {absolute(rule[key]) for rule in rules for key in ("source", "target", "route") if key in rule}
    roots.update(absolute(path) for rule in rules for path in rule.get("independentRoutes", {}).values())
    return roots


def project_writes(manifest, boundary, candidate, previous, roots):
    if manifest.get("opaque"):
        raise Conflict(f"Activation writes unknown for: {', '.join(manifest['opaque'])}")
    for value in manifest.get("activationWrites", []):
        path = absolute(value)
        resolved = path.resolve()
        if any(overlaps(path, root) or overlaps(resolved, root) for root in roots):
            raise Conflict(f"Activation hook can write protected data: {path}")

    known = {path: previous.get(path, set()) | candidate.get(path, set())
             for path in previous.keys() | candidate.keys()}
    backup_ext = os.environ.get("HOME_MANAGER_BACKUP_EXT", "")
    backup_command = os.environ.get("HOME_MANAGER_BACKUP_COMMAND", "")
    for path in sorted(known):
        # Even an unrelated lexical path can reach protected data via a parent
        # symlink. Never let embedded HM use such an unproven write path.
        info = boundary.entry(path)
        if path in candidate and any(path != root and root.is_relative_to(path) for root in roots):
            raise Conflict(f"Home Manager would link an ancestor of a protected root: {path}")
        if (path in candidate and any(overlaps(path, root) for root in roots)
                and any(not Path(value).resolve().is_relative_to("/nix/store") for value in candidate[path])):
            raise Conflict(f"Home Manager link has an external referent in a protected root: {path}")
        if info is None:
            continue
        if path in candidate:
            if any(overlaps(path, root) for root in roots) and not owned_link(path, known):
                raise Conflict(f"Home Manager link would displace protected data: {path}")
            if not stat.S_ISLNK(info.st_mode):
                if backup_command:
                    raise Conflict(f"Custom Home Manager backup command has unknown effects: {path}")
                if backup_ext:
                    backup = absolute(str(path) + "." + backup_ext)
                    if any(overlaps(backup, root) for root in roots):
                        raise Conflict(f"Home Manager backup would write a protected location: {backup}")
        elif (path.is_symlink() and re.match(r"/nix/store/[^/]+-home-manager-files/", os.readlink(path))
              and any(overlaps(path, root) for root in roots) and not owned_link(path, previous)):
            raise Conflict(f"Home Manager cleanup could remove an unproven protected link: {path}")
    return known


def route_state(boundary, path, generated):
    info = boundary.entry(path)
    if info is None:
        return "absent"
    boundary.reject_mounts(path)
    if stat.S_ISLNK(info.st_mode) and owned_link(path, generated):
        return "scaffold"
    if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
        raise Conflict(f"Unsafe application root: {path}")
    if stat.S_ISDIR(info.st_mode) and generated_tree(path, generated):
        return "scaffold"
    return "data"


def assess_root(boundary, path, generated):
    try:
        return route_state(boundary, path, generated)
    except (Conflict, OSError):
        return "unknown"


def inspect_routes(manifest, boundary, generated):
    return {group: [{"owner": rule["owner"], "route": rule.get("route", rule["target"]),
                    "roots": {key: {"path": rule[key], "state": assess_root(boundary, Path(rule[key]), generated)}
                              for key in ("source", "target")},
                    "consumers": rule.get("consumers", {}), "userService": rule.get("serviceRoutes", {})}
                   for rule in rules]
            for group, rules in groups(manifest).items()}


def activation_gate(manifest, boundary, generation, previous, incumbent, sessions_active):
    home, state = manifest_paths(manifest)
    if generation is None and manifest["rules"]:
        raise Unsupported("Activation requires a realised candidate Home Manager generation")
    old_manifest = {}
    if incumbent and (incumbent / "home-layout-manifest.json").is_file():
        old_manifest = json.loads((incumbent / "home-layout-manifest.json").read_text())
        if old_manifest["home"] != str(home):
            raise Unsupported("The incumbent and candidate HOME differ")
    current = groups(manifest)
    old = groups(old_manifest) if old_manifest else {}
    if not (current or old):
        return
    with boundary.directory(home) as home_fd:
        if os.fstat(home_fd).st_uid != boundary.uid:
            raise Unsupported(f"HOME is unavailable or has an unexpected owner: {home}")

    # HM uses its current-home GC root for cleanup. Account for it separately
    # from the installed system profile, which can already have changed.
    old_generations = active_generations(home, manifest.get("stateHome"), old_manifest.get("stateHome"))
    old_generations.update(path for path in (previous, incumbent) if path)
    old_files = {}
    merge_generation_files(old_files, home, old_generations)

    roots = protected_roots(manifest["rules"] + old_manifest.get("rules", []))
    generated = project_writes(manifest, boundary, generation_files(home, generation), old_files, roots)
    print("Home migration activation writes: safe for protected roots", file=sys.stderr)

    try:
        runs = read_runs(boundary, state)
        journals_known = True
    except (Conflict, OSError) as error:
        print(f"Home migration journals need review: {error}", file=sys.stderr)
        runs = []
        journals_known = False
    for group, rules in old.items():
        if group not in current and any(route_state(boundary, path, generated) == "data"
                                        for path in protected_roots(rules)):
            raise Conflict(f"[{group}] runtime continuity: removing a route with existing data")

    for group, rules in current.items():
        incumbent_rules = old.get(group, [])
        selected = [absolute(rule.get("route", rule["target"])) for rule in rules]
        legacy = [absolute(rule["source"]) for rule in rules]
        intended = [absolute(rule["target"]) for rule in rules]
        if selected not in (legacy, intended):
            raise Conflict(f"[{group}] runtime continuity: unknown or mixed selected route")
        for path in selected:
            if not path.is_relative_to(home):
                resolve_external(boundary, manifest, path)
        held = selected == legacy and selected != intended
        for rule in rules:
            variables = set(rule.get("serviceVariables", [])) | rule.get("independentRoutes", {}).keys()
            consumers = rule.get("consumers", {})
            if any(rule.get("serviceRoutes", {}).get(name) != consumers.get(name) for name in variables):
                raise Conflict(f"[{group}] runtime continuity: shell and user-service routes differ")
            if held and group == "claude" and "CLAUDE_CONFIG_DIR" in consumers:
                raise Conflict("[claude] runtime continuity: legacy account state requires unsetting CLAUDE_CONFIG_DIR")
        if group in old:
            before = {rule["source"]: rule for rule in incumbent_rules}
            old_routes = [absolute(before[str(path)].get("route", before[str(path)]["target"]))
                          if str(path) in before else None for path in legacy]
            if any(rule.get("independentRoutes", {}) != before.get(rule["source"], {}).get("independentRoutes", {})
                   for rule in rules):
                raise Conflict(f"[{group}] runtime continuity: independent consumer routes changed")
        else:
            adopted = manifest.get("adopt", {}).get(group)
            old_routes = {"legacy": legacy, "intended": intended}.get(adopted)

        # An obstruction on an unselected path can prevent migration without
        # preventing an unrelated activation on a verified incumbent route.
        source_states = [assess_root(boundary, path, generated) for path in legacy]
        target_states = [assess_root(boundary, path, generated) for path in intended]
        incumbent_only = protected_roots(incumbent_rules) - protected_roots(rules)
        incumbent_states = {assess_root(boundary, path, generated) for path in incumbent_only}
        data = {"data", "unknown"}
        has_old = any(state in data and source != target
                      for state, source, target in zip(source_states, legacy, intended))
        has_new = bool(data.intersection(target_states))
        independent = {absolute(path) for rule in rules for path in rule.get("independentRoutes", {}).values()}
        independent_states = {assess_root(boundary, path, generated) for path in independent}
        incumbent_pending = bool(data.intersection(incumbent_states))
        pending = has_old or has_new or incumbent_pending or bool(data.intersection(independent_states))
        if "unknown" in independent_states:
            raise Conflict(f"[{group}] runtime continuity: unsafe independent consumer root")
        selected_states = source_states if held else target_states
        if "unknown" in selected_states:
            raise Conflict(f"[{group}] runtime continuity: unsafe selected root")
        if incumbent_pending:
            assessment = "incumbent roots outside the candidate require assessment"
        elif has_old and has_new:
            assessment = "both locations need assessment"
        else:
            assessment = "legacy pending" if has_old else "target present" if has_new else "fresh"
        print(f"[{group}] migration assessment: {assessment}", file=sys.stderr)

        selected_has_data = "data" in selected_states or "data" in independent_states
        unfinished = any(run["header"]["group"] == group and not run["finished"] for run in runs)
        if unfinished and not (held and old_routes == selected and selected_has_data):
            raise Conflict(f"[{group}] runtime continuity: recover the interrupted group before routing")
        if pending and old_routes is None:
            raise Conflict(f"[{group}] runtime continuity: inventory and declare the verified incumbent route")
        if held:
            if pending and old_routes == intended and selected_has_data:
                if sessions_active:
                    raise Conflict(f"[{group}] runtime continuity: exclude active sessions and writers before rollback")
                if not verified_rollback(manifest, group, runs, boundary):
                    raise Conflict(f"[{group}] runtime continuity: legacy route requires a verified rollback")
            elif pending and (old_routes != selected or not selected_has_data):
                raise Conflict(f"[{group}] runtime continuity: no verified legacy incumbent")
            if any(new == "data" and prior != "data" for prior, new in zip(source_states, target_states)):
                raise Conflict(f"[{group}] runtime continuity: legacy route would expose an incomplete group")
        else:
            changed = old_routes is not None and selected != old_routes
            if changed and pending:
                if sessions_active:
                    raise Conflict(f"[{group}] runtime continuity: exclude active sessions and writers before cutover")
                reconciled = (journals_known and group in manifest.get("reconciled", []) and not has_old and has_new
                              and not plan({**manifest, "rules": rules}, boundary, activation=True,
                                           generated=generated))
                if old_routes != legacy or not (reconciled or verified_transfer(manifest, group, runs, boundary)):
                    raise Conflict(f"[{group}] runtime continuity: intended route requires a verified transfer")
            elif has_old:
                # An unchanged intended route may already be split. Do not
                # start more writers against an unresolved target.
                if not verified_transfer(manifest, group, runs, boundary, unchanged=True):
                    raise Conflict(f"[{group}] runtime continuity: legacy state remains or route is split")
        print(f"[{group}] runtime continuity: {'legacy held' if held else 'intended route admitted'}",
              file=sys.stderr)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True).encode()).hexdigest()


def payload(boundary, path, mount, excluded=(), mutable_dirs=(), *, copy=False, sync=False):
    """Inventory from pinned descriptors. Store only the resulting fingerprint."""
    entries, links = [], {}
    excluded, mutable_dirs = set(excluded), set(mutable_dirs)
    size = 0

    def visit(parent, name, relative):
        nonlocal size
        if relative in excluded:
            return
        with opened_entry(parent, name) as (entry, info):
            if boundary.mount(entry, path, refresh=False) != mount or info.st_uid != boundary.uid:
                raise Unsupported(f"Unsupported payload ownership or mount: {path}")
            mode = info.st_mode
            metadata = [relative, mode, info.st_uid, info.st_gid,
                        None if relative in mutable_dirs else info.st_mtime_ns]
            if stat.S_ISREG(mode) or stat.S_ISLNK(mode):
                key = (info.st_dev, info.st_ino)
                first, seen, count = links.get(key, (relative, 0, info.st_nlink))
                links[key] = (first, seen + 1, count)
                metadata.append(first)
            if stat.S_ISLNK(mode):
                pinned_name = f"/proc/self/fd/{parent}/{name}"
                attrs = [[key, os.getxattr(pinned_name, key, follow_symlinks=False).hex()]
                         for key in sorted(os.listxattr(pinned_name, follow_symlinks=False))]
                entries.append([metadata, attrs, os.readlink("", dir_fd=entry)])
                return
            if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise Unsupported(f"Special entries require a topology-specific plan: {path}")
            fd = os.open(f"/proc/self/fd/{entry}", os.O_RDONLY | os.O_NOATIME)
            try:
                attrs = [[key, os.getxattr(fd, key).hex()] for key in sorted(os.listxattr(fd))]
                if stat.S_ISDIR(mode):
                    entries.append([metadata, attrs])
                    for child in sorted(os.listdir(fd)):
                        visit(fd, child, str(Path(relative) / child))
                else:
                    allocated = info.st_blocks * 512
                    if not seen:
                        size += min(info.st_size, allocated)
                    with os.fdopen(os.dup(fd), "rb") as stream:
                        contents = hashlib.file_digest(stream, "sha256").hexdigest()
                    entries.append([metadata, attrs, info.st_size, allocated < info.st_size, contents])
                if sync:
                    os.fsync(fd)
            finally:
                os.close(fd)

    boundary.reject_mounts(path)
    with boundary.directory(path.parent) as parent:
        if boundary.mount(parent, path) != mount:
            raise Conflict(f"Mount changed during inventory: {path}")
        visit(parent, path.name, ".")
        if sync:
            os.fsync(parent)
    if copy and any(seen != count for _, seen, count in links.values()):
        raise Unsupported(f"Cross-mount transfer cannot preserve hard links outside the payload: {path}")
    return digest(entries), size


@contextmanager
def opened_entry(parent, name):
    fd = os.open(name, os.O_PATH | os.O_NOFOLLOW, dir_fd=parent)
    try:
        info = os.fstat(fd)
        yield fd, info
        current = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if (identity(current) != identity(info) or current.st_ctime_ns != info.st_ctime_ns
                or current.st_mtime_ns != info.st_mtime_ns):
            raise Conflict("Payload changed during inventory")
    finally:
        os.close(fd)


def write_journal(log, event):
    log.write(json.dumps({**event, "recordHash": digest(event)}, ensure_ascii=True) + "\n")
    log.flush()
    os.fsync(log.fileno())


def run_context(manifest, group):
    # The completed transfer also applies to the generation selecting the
    # other route. Moving roots or changing reference policy invalidates it.
    rules = [{k: v for k, v in rule.items() if k not in ("route", "consumers", "serviceRoutes")}
             for rule in groups(manifest)[group]]
    return {"host": manifest.get("host") or socket.gethostname(), "machine": socket.gethostname(),
            "uid": os.geteuid(), "home": manifest["home"], "state": manifest["state"],
            "rules": digest(rules)}


def journal_data(boundary, run, *, append=False):
    @contextmanager
    def open_log():
        with boundary.directory(run) as parent:
            if os.fstat(parent).st_mode & 0o077 or os.fstat(parent).st_uid != boundary.uid:
                raise Unsupported(f"Untrusted migration journal directory: {run}")
            flags = os.O_RDWR | os.O_APPEND if append else os.O_RDONLY
            fd = os.open("operations.jsonl", flags | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            with os.fdopen(fd, "a+" if append else "r", encoding="utf-8") as log:
                info = os.fstat(log.fileno())
                if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                        or info.st_uid != boundary.uid or info.st_mode & 0o077):
                    raise Unsupported(f"Untrusted migration journal: {run}")
                yield log
    return open_log()


def read_runs(boundary, state):
    if boundary.entry(state) is None:
        return []
    check_state(boundary, state)
    result = []
    with boundary.directory(state) as parent:
        names = sorted(os.listdir(parent))
    for name in names:
        run = state / name
        if not re.fullmatch(r"\d{8}T\d{6}-[0-9a-f]{32}", name):
            raise Conflict(f"Unexpected entry in migration journal directory: {run}")
        try:
            with journal_data(boundary, run) as log:
                events = [json.loads(line) for line in log]
            for event in events:
                if event.pop("recordHash", None) != digest(event):
                    raise ValueError()
            header = events[0]
            if header.get("version") != 2 or header.get("event") != "begin" or header.get("run") != name:
                raise ValueError()
            finished = events[-1].get("event") == "finished"
            if finished and {event.get("index") for event in events[1:] if event["event"] == "done"} != set(
                    range(len(header["operations"]))):
                raise ValueError()
        except (FileNotFoundError, ValueError, IndexError, AttributeError, KeyError, TypeError) as error:
            raise Conflict(f"Preserve and review an incomplete or older migration journal: {run}") from error
        result.append({"path": run, "header": header, "events": events[1:], "finished": finished})
    return result


def approved_operations(actions, boundary):
    operations = []
    storage = {}
    moves = [item for item in actions if item["action"] == "move"]
    for index, action in enumerate(moves):
        source, target = Path(action["source"]), Path(action["target"])
        left, right = action["sourceMount"], action["targetMount"]
        copy = left != right
        children = [item for item in moves if item is not action and Path(item["source"]).is_relative_to(source)]
        if (copy and children) or any(item["sourceMount"] != item["targetMount"] for item in children):
            raise Unsupported(f"Nested cross-mount transfer requires a topology-specific plan: {source}")
        target_children = [Path(item["target"]).relative_to(target) for item in moves
                           if item is not action and Path(item["target"]).is_relative_to(target)]
        source_exclude = [Path(item["source"]).relative_to(source) for item in children]
        src_dirs = {str(parent) for child in source_exclude for parent in child.parents}
        dst_dirs = {str(parent) for child in target_children for parent in child.parents}
        mutable = sorted(src_dirs | dst_dirs)
        excludes = list(map(str, source_exclude))
        target_excludes = list(map(str, target_children))
        if action["backup"]:
            fingerprint, _ = payload(boundary, target, right)
            operations.append({"op": "rename", "kind": "scaffold", "source": str(target),
                               "target": None, "sibling": f"scaffold-{index}", "entry": list(action["backup"]),
                               "left": right, "right": right, "payload": fingerprint,
                               "exclude": [], "targetExclude": [], "mutable": []})
        fingerprint, size = payload(boundary, source, left, excludes, mutable, copy=copy)
        if copy:
            _, required = storage.get(right, (target.parent, 0))
            storage[right] = (target.parent, required + size)
        operations.append({"op": "copy" if copy else "rename", "kind": "legacy",
                           "source": str(source), "target": str(target), "entry": list(action["entry"]),
                           "left": left, "right": right, "payload": fingerprint, "bytes": size,
                           "exclude": excludes, "targetExclude": target_excludes, "mutable": mutable})
    for path, size in storage.values():
        boundary.check_capacity(path, size)
    return operations


def observe(boundary, path, mount):
    if boundary.mount_at(path.parent) != mount:
        raise Conflict(f"Mount changed after planning: {path}")
    info = boundary.entry(path)
    return list(identity(info)) if info else None


def pin_operation_parents(operations, boundary):
    moved = [Path(op["source"]) for op in operations if op["op"] == "rename"]
    for op in operations:
        source = Path(op["source"])
        parents = [source.parent, Path(op["target"]).parent if op["target"] else source.parent]
        if "proof" in op:
            parents.append(Path(op["proof"]["target"]).parent)
        # Pin ancestors that will still exist after later operations in this
        # group, including a parent move after the Bun cache was detached.
        for index, parent in enumerate(parents):
            while any(parent.is_relative_to(root) for root in moved):
                parent = parent.parent
            parents[index] = boundary.anchor(parent)
        op["anchors"] = parents
    return operations


def check_payload(boundary, op, path, *, target=False, sync=False):
    fingerprint, _ = payload(boundary, path, op["right"] if target else op["left"],
                             op["targetExclude"] if target else op["exclude"], op["mutable"],
                             copy=op["op"] == "copy", sync=sync)
    if fingerprint != op["payload"]:
        raise Conflict(f"Payload changed after planning: {path}")


def commit_move(boundary, source, target, entry, mount):
    with (boundary.directory(source.parent) as source_fd,
          boundary.directory(target.parent, create=True) as target_fd):
        if (boundary.mount(source_fd, source) != mount or boundary.mount(target_fd, target) != mount
                or not boundary.matches(source_fd, source, target_fd, target, entry[0])):
            raise Unsupported(f"Move parents changed after planning: {source} -> {target}")
        boundary.reject_mounts(source)
        current = os.stat(source.name, dir_fd=source_fd, follow_symlinks=False)
        if list(identity(current)) != entry or current.st_uid != boundary.uid:
            raise Conflict(f"Move source changed after planning: {source}")
        intent = safety.MoveNew(boundary.uid, safety.Leaf(source_fd, source.name),
                                safety.Leaf(target_fd, target.name), entry[2])
        safety.execute_move(intent, confirmed=True)


def new_stage(boundary, log, run, index, op, source, target, rsync):
    if not rsync:
        raise Unsupported("Cross-mount transfer requires the packaged rsync")
    boundary.check_capacity(target.parent, op["bytes"])
    stage = target.parent / f".home-layout-{run.name}-{index}-{uuid.uuid4().hex[:12]}-stage"
    write_journal(log, {"event": "staging", "index": index, "stage": str(stage)})
    with boundary.directory(target.parent, create=True) as parent:
        if boundary.mount(parent, target) != op["right"]:
            raise Conflict(f"Destination mount changed before staging: {target}")
        os.mkdir(stage.name, mode=0o700, dir_fd=parent)
        os.fsync(parent)
    staged = stage / "payload"
    with (boundary.directory(source.parent) as left, boundary.directory(stage) as right):
        if boundary.mount(left, source) != op["left"] or boundary.mount(right, target) != op["right"]:
            raise Conflict("Mount changed before the staged copy")
        source_arg = f"/proc/self/fd/{left}/{source.name}"
        if op["entry"][2] == stat.S_IFDIR:
            source_arg += "/"
        subprocess.run([rsync, "--archive", "--one-file-system", "--hard-links", "--acls", "--xattrs", "--sparse",
                        "--numeric-ids", "--atimes", "--open-noatime", "--modify-window=-1", "--",
                        source_arg, f"/proc/self/fd/{right}/payload"],
                       pass_fds=(left, right), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    check_payload(boundary, op, source)
    check_payload(boundary, op, staged, target=True, sync=True)
    entry = observe(boundary, staged, op["right"])
    ready = {"event": "ready", "index": index, "stage": str(staged), "entry": entry}
    write_journal(log, ready)
    return ready


def check_move_entries(boundary, op, move_from, move_entry, staged, after, events, *, sync=False):
    target = Path(op["target"])
    if after is not None:
        intended = any(event["event"] == "intent" for event in events)
        if not intended or after != move_entry or staged is not None:
            raise Conflict(f"Cannot reconcile existing destination without replacing data: {target}")
        check_payload(boundary, op, target, target=True, sync=sync)
    else:
        if staged != move_entry:
            raise Conflict(f"Migration source changed or is missing: {move_from}")
        check_payload(boundary, op, move_from, target=op["op"] == "copy", sync=sync)


def execute_operation(boundary, log, run, index, op, events, rsync):
    source, target = Path(op["source"]), Path(op["target"])
    before = observe(boundary, source, op["left"])
    after = observe(boundary, target, op["right"])
    if op["op"] == "copy":
        if before != op["entry"]:
            raise Conflict(f"Copy source changed after planning: {source}")
        check_payload(boundary, op, source)
        ready = next((event for event in reversed(events) if event["event"] == "ready"), None)
        if ready is None:
            if after:
                raise Conflict(f"Copy target is already occupied: {target}")
            ready = new_stage(boundary, log, run, index, op, source, target, rsync)
        move_from, move_entry = Path(ready["stage"]), ready["entry"]
        staged = observe(boundary, move_from, op["right"])
    else:
        move_from, move_entry, staged = source, op["entry"], before

    check_move_entries(boundary, op, move_from, move_entry, staged, after, events, sync=True)
    if after is not None:
        with boundary.directory(move_from.parent) as left:
            os.fsync(left)
    else:
        write_journal(log, {"event": "intent", "index": index, "source": str(move_from),
                            "target": str(target), "entry": move_entry})
        if proof := op.get("proof"):
            verify_authoritative(boundary, op, proof)
        commit_move(boundary, move_from, target, move_entry, op["right"])
    write_journal(log, {"event": "done", "index": index, "entry": move_entry})


def check_completed_operation(boundary, operation, complete):
    target = Path(operation["target"])
    if observe(boundary, target, operation["right"]) != complete["entry"]:
        raise Conflict(f"Earlier committed step changed before recovery: {target}")
    check_payload(boundary, operation, target, target=True)
    if operation["kind"] != "scaffold":
        source = Path(operation["source"])
        remaining = observe(boundary, source, operation["left"])
        if operation["op"] == "copy" and remaining == operation["entry"]:
            check_payload(boundary, operation, source)
        elif remaining is not None or operation["op"] == "copy":
            raise Conflict(f"Earlier committed step has an unexpected legacy entry: {source}")


def preflight_retirement_step(boundary, operation, prior, complete):
    if complete is not None:
        check_completed_operation(boundary, operation, complete)
        return
    source, target = Path(operation["source"]), Path(operation["target"])
    before = observe(boundary, source, operation["left"])
    after = observe(boundary, target, operation["right"])
    check_move_entries(boundary, operation, source, operation["entry"], before, after, prior)
    # A published move without a completion record still needs its source
    # parent to be available for the recovery fsync.
    with boundary.directory(source.parent) as left:
        if after is None:
            boundary.writable(left, source.parent)
            with boundary.directory(target.parent, nearest=True) as right:
                boundary.writable(right, target.parent)


def execute_run(boundary, journal, log, rsync):
    run, header, events = journal["path"], journal["header"], journal["events"]
    retiring = header["mode"] in ("retire", "retire-equal")
    steps = []
    for index, operation in enumerate(header["operations"]):
        for anchor in operation["anchors"]:
            if boundary.anchor(Path(anchor[0])) != anchor:
                raise Conflict(f"Planned parent or mount changed: {anchor[0]}")
        if proof := operation.get("proof"):
            verify_authoritative(boundary, operation, proof)
        prior = [event for event in events if event.get("index") == index]
        complete = next((event for event in prior if event["event"] == "done"), None)
        # Retirement moves independent roots into private quarantine paths.
        # Check the whole group's observed state before advancing any step.
        if retiring:
            preflight_retirement_step(boundary, operation, prior, complete)
        steps.append((operation, prior, complete))
    for index, (operation, prior, complete) in enumerate(steps):
        if complete is None:
            execute_operation(boundary, log, run, index, operation, prior, rsync)
        else:
            check_completed_operation(boundary, operation, complete)
    write_journal(log, {"event": "finished"})


def quarantine_target(run, source, sibling):
    return str(Path(source).parent / f".home-layout-{run}-{sibling}/payload")


def commit_batch(boundary, state, header, rsync):
    name = datetime.datetime.now().strftime("%Y%m%dT%H%M%S-") + uuid.uuid4().hex
    run = state / name
    header = {"event": "begin", "version": 2, "run": name, **header}
    for op in header["operations"]:
        if op["target"] is None:
            op["target"] = quarantine_target(name, op["source"], op["sibling"])
    print(f"Migration journal: {run}", file=sys.stderr, flush=True)
    with boundary.directory(state, create=True) as parent:
        os.mkdir(name, mode=0o700, dir_fd=parent)
        os.fsync(parent)
        with boundary.directory(run) as directory:
            fd = os.open("operations.jsonl", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=directory)
            with os.fdopen(fd, "w", encoding="utf-8") as log:
                os.fsync(directory)
                write_journal(log, header)
                execute_run(boundary, {"path": run, "header": header, "events": []}, log, rsync)


def done_entry(run, index):
    return next((event["entry"] for event in reversed(run["events"])
                 if event.get("index") == index and event["event"] == "done"), None)


def disposition(runs, parent, mode):
    return next((run for run in runs if run["finished"] and run["header"].get("parent") == parent["header"]["run"]
                 and run["header"]["mode"] == mode), None)


def verify_authoritative(boundary, operation, proof, *, unchanged=False):
    target = Path(proof["target"])
    if observe(boundary, target, proof["mount"]) != proof["entry"]:
        raise Conflict(f"Authoritative target identity has changed: {target}")
    if not unchanged:
        fingerprint, _ = payload(boundary, target, proof["mount"], proof.get("exclude", ()),
                                 operation["mutable"], copy=True)
        if fingerprint != operation["payload"]:
            raise Conflict(f"Authoritative target has changed: {target}")


def verified_transfer(manifest, group, runs, boundary, *, unchanged=False, retained_only=False):
    context = run_context(manifest, group)
    for run in reversed(runs):
        header = run["header"]
        if (not run["finished"] or header["mode"] not in ("apply", "retire-equal") or header["group"] != group
                or header["context"] != context or disposition(runs, run, "rollback")):
            continue
        if header["mode"] == "retire-equal":
            if retained_only:
                continue
            try:
                for op in header["operations"]:
                    if boundary.entry(Path(op["source"])) is not None:
                        return False
                    verify_authoritative(boundary, op, op["proof"], unchanged=unchanged)
            except (Conflict, OSError):
                return False
            return True
        retired = disposition(runs, run, "retire")
        if retired and disposition(runs, retired, "rollback"):
            retired = None
        operations = [(index, op) for index, op in enumerate(header["operations"]) if op["kind"] == "legacy"]
        if not operations:
            continue
        # A run must account for every incumbent root still present. A separate
        # newly created legacy root remains a split even if another was copied.
        copies = {op["source"] for _, op in operations if op["op"] == "copy" and not retired}
        if retained_only and not copies:
            continue
        try:
            if any(boundary.entry(Path(rule["source"])) is not None and rule["source"] not in copies
                   for rule in groups(manifest)[group]):
                return False
            for index, op in operations:
                source, target = Path(op["source"]), Path(op["target"])
                if observe(boundary, target, op["right"]) != done_entry(run, index):
                    return False
                if not unchanged:
                    check_payload(boundary, op, target, target=True)
                if op["source"] in copies:
                    if observe(boundary, source, op["left"]) != op["entry"]:
                        return False
                    check_payload(boundary, op, source)
        except (Conflict, OSError):
            return False
        return True
    return False


def verified_rollback(manifest, group, runs, boundary):
    context = run_context(manifest, group)
    for original in reversed(runs):
        header = original["header"]
        if (header["mode"] not in ("apply", "retire-equal") or header["group"] != group
                or header["context"] != context or not disposition(runs, original, "rollback")):
            continue
        try:
            for op in header["operations"]:
                if op["kind"] == "scaffold":
                    continue
                source = Path(op["source"])
                if observe(boundary, source, op["left"]) != op["entry"]:
                    return False
                check_payload(boundary, op, source)
        except (Conflict, OSError):
            return False
        return True
    return False


def plan_group(manifest, group, boundary, generated, *, retire_equal=False):
    subset = {**manifest, "rules": groups(manifest)[group]}
    if retire_equal:
        return [], pin_operation_parents(plan_equal_retirement(subset, boundary), boundary)
    actions = plan(subset, boundary, generated=generated, compare_collisions=True)
    if moves := {action["source"] for action in actions if action["action"] == "move"}:
        for rule in subset["rules"]:
            if (rule["source"] not in moves and rule["source"] != rule["target"]
                    and route_state(boundary, Path(rule["target"]), generated) == "data"):
                raise Conflict(f"[{group}] group is already split; verify an authoritative route before applying")
    operations = approved_operations(actions, boundary) if all(action["action"] == "move" for action in actions) else []
    return actions, pin_operation_parents(operations, boundary)


def authority(manifest, group, operations, mode="apply"):
    return digest({"context": run_context(manifest, group), "manifest": digest(manifest),
                   "group": group, "operations": operations, "mode": mode})


def plan_equal_retirement(manifest, boundary):
    operations = []
    rules = manifest["rules"]
    for index, rule in enumerate(rules):
        source, target = Path(rule["source"]), Path(rule["target"])
        if source == target:
            continue
        if any(index != other_index and (overlaps(source, Path(other["source"]))
                                         or overlaps(target, Path(other["target"])))
               for other_index, other in enumerate(rules)):
            raise Unsupported("Nested matching copies require a topology-specific retirement plan")
        left, right = boundary.mount_at(source.parent), boundary.mount_at(target.parent)
        before, authoritative = observe(boundary, source, left), observe(boundary, target, right)
        if before is None and authoritative is None:
            continue
        if not before or not authoritative or before[2] not in (stat.S_IFDIR, stat.S_IFREG):
            raise Conflict(f"Retirement needs two supported, matching copies: {source} -> {target}")
        fingerprint, _ = payload(boundary, source, left, copy=True)
        intended, _ = payload(boundary, target, right, copy=True)
        if fingerprint != intended:
            raise Conflict(f"Retirement needs matching bytes, topology and metadata: {source} -> {target}")
        if before[2] == stat.S_IFDIR:
            for path in tree(target):
                if path.is_symlink():
                    link = os.readlink(path)
                    if (relocated_absolute(link, rules) is not None or
                            (not os.path.isabs(link) and not (path.parent / link).resolve().is_relative_to(target))):
                        raise Conflict(f"Review the link before retiring the legacy copy: {path}")
        for relative in rule.get("references", []):
            path = target / relative
            if boundary.entry(path) is not None:
                if path.is_symlink() or not path.is_file() or check_reference(
                        path, path, source, target, Path(manifest["home"])):
                    raise Conflict(f"Review the reference before retiring the legacy copy: {path}")
        operations.append({"op": "rename", "kind": "equal-retirement", "source": str(source),
                           "target": None, "sibling": f"equal-retired-{index}", "entry": before,
                           "left": left, "right": left, "payload": fingerprint,
                           "exclude": [], "targetExclude": [], "mutable": [],
                           "proof": {"target": str(target), "entry": authoritative, "mount": right}})
    return operations


def other_operation(boundary, op, source, target, entry, mount, kind, sibling=None, *, reverse=False):
    if not entry or observe(boundary, source, mount) != entry:
        raise Conflict(f"Recorded source identity has changed: {source}")
    if target is not None and observe(boundary, target, mount) is not None:
        raise Conflict(f"Restore destination is occupied: {target}")
    check_payload(boundary, op, source, target=reverse)
    source_exclude, target_exclude = op["exclude"], op["targetExclude"]
    if reverse:
        source_exclude, target_exclude = target_exclude, source_exclude
    return {**op, "op": "rename", "kind": kind, "source": str(source),
            "target": str(target) if target is not None else None, "sibling": sibling,
            "entry": entry, "left": mount, "right": mount,
            "exclude": source_exclude, "targetExclude": target_exclude}


def retirement_sources(parent, runs):
    header = parent["header"]
    if (not parent["finished"] or header["mode"] != "apply"
            or disposition(runs, parent, "rollback") or disposition(runs, parent, "retire")):
        raise Conflict("Retirement requires a completed, unretired transfer")
    return [(index, op) for index, op in enumerate(header["operations"]) if op["op"] == "copy"]


def retirement_proof(parent, index, operation):
    return {"target": operation["target"], "mount": operation["right"],
            "entry": done_entry(parent, index), "exclude": operation["targetExclude"]}


def validate_retirement_recovery(journal, runs):
    header = journal["header"]
    parent = next((run for run in runs if run["header"]["run"] == header.get("parent")), None)
    if (parent is None or parent["header"]["group"] != header["group"]
            or parent["header"]["context"] != header["context"]):
        raise Conflict("The interrupted retirement has no matching transfer authority")
    approved = retirement_sources(parent, runs)
    if len(approved) != len(header["operations"]):
        raise Conflict("The interrupted retirement does not match the completed transfer")
    for recorded, (index, operation) in zip(header["operations"], approved):
        proof = retirement_proof(parent, index, operation)
        sibling = f"retired-{index}"
        expected = {key: operation[key] for key in ("source", "entry", "left", "payload", "exclude", "mutable")}
        expected.update(op="rename", kind="retirement", sibling=sibling, right=operation["left"],
                        target=quarantine_target(header["run"], operation["source"], sibling))
        if (any(recorded.get(key) != value for key, value in expected.items())
                or recorded.get("proof", proof) != proof):
            raise Conflict("The interrupted retirement does not match the completed transfer")
        # Earlier journals omitted the proof. Derive it from the completed
        # parent rather than using the current target as the expected identity.
        recorded["proof"] = proof
        recorded["targetExclude"] = operation["exclude"]


def disposition_operations(boundary, parent, runs, mode):
    header = parent["header"]
    if not parent["finished"] or disposition(runs, parent, "rollback"):
        raise Conflict("Select a completed run that has not been rolled back")
    operations = list(enumerate(header["operations"]))
    if mode == "retire":
        result = []
        for index, op in retirement_sources(parent, runs):
            proof = retirement_proof(parent, index, op)
            verify_authoritative(boundary, op, proof)
            retirement = other_operation(boundary, op, Path(op["source"]), None, op["entry"],
                                         op["left"], "retirement", f"retired-{index}")
            result.append({**retirement, "proof": proof, "targetExclude": op["exclude"]})
        return result

    retired = disposition(runs, parent, "retire")
    if retired and not disposition(runs, retired, "rollback"):
        raise Conflict("Restore the separately retired source before reversing the transfer")
    result = []
    cleared = set()
    for index, op in reversed(operations):
        source, target = Path(op["source"]), Path(op["target"])
        if op["op"] == "copy":
            if observe(boundary, source, op["left"]) != op["entry"]:
                raise Conflict(f"Original copy has changed: {source}")
            check_payload(boundary, op, source)
        reverse = other_operation(boundary, op, target, None if op["op"] == "copy" or source in cleared else source,
                                  done_entry(parent, index), op["right"], "restore",
                                  f"rollback-{index}", reverse=True)
        if op["op"] == "copy":
            reverse["proof"] = {"target": str(source), "mount": op["left"], "entry": op["entry"],
                                "exclude": op["exclude"]}
        if source in cleared and op["op"] != "copy":
            reverse["target"] = str(source)
        result.append(reverse)
        cleared.add(target)
    return result


def mutate(manifest, mode, group, generated, rsync, *, expect=None, run_id=None, require_token=True):
    home, state = manifest_paths(manifest)
    if group not in groups(manifest):
        raise Conflict(f"Unknown migration group: {group}")
    boundary = MoveBoundary()
    with boundary.directory(home) as home_fd:
        if os.fstat(home_fd).st_uid != boundary.uid:
            raise Unsupported(f"Apply must run as the HOME directory owner: {home}")
        boundary.mount(home_fd, home)
        try:
            fcntl.flock(home_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Conflict(f"Another migration holds the HOME lock: {home}") from error
        rules = groups(manifest)[group]
        pids = busy({pattern for rule in rules for pattern in rule.get("processes", [])},
                    protected_roots(rules))
        if pids:
            raise Conflict(f"Close applications before migration (PIDs: {', '.join(pids)})")
        runs = read_runs(boundary, state)
        unfinished = [run for run in runs if not run["finished"]]
        context = run_context(manifest, group)
        if mode == "recover":
            if (len(unfinished) != 1 or unfinished[0]["header"]["run"] != run_id
                    or unfinished[0]["header"]["group"] != group or unfinished[0]["header"]["context"] != context
                    or unfinished[0]["header"]["manifest"] != digest(manifest)):
                raise Conflict("Recovery requires the outstanding run, original generation and group")
            journal = unfinished[0]
            if journal["header"]["mode"] == "retire":
                validate_retirement_recovery(journal, runs)
            with journal_data(boundary, journal["path"], append=True) as log:
                execute_run(boundary, journal, log, rsync)
            return []
        if unfinished:
            raise Conflict(f"Recover outstanding run before starting a new one: {unfinished[0]['path']}")
        actions, parent = [], None
        if mode in ("apply", "retire-equal"):
            if mode == "apply" and verified_transfer(manifest, group, runs, boundary, unchanged=True, retained_only=True):
                return []
            actions, operations = plan_group(manifest, group, boundary, generated, retire_equal=mode == "retire-equal")
            if any(action["action"] != "move" for action in actions):
                raise Unsupported("Replacement requires exclusive ownership and operator repair; batch refused")
            if operations and require_token and expect != authority(manifest, group, operations, mode):
                raise Conflict("The plan changed or has no matching --expect token")
        else:
            parent = next((item for item in runs if item["header"]["run"] == run_id
                           and item["header"]["group"] == group and item["header"]["context"] == context), None)
            if parent is None:
                raise Conflict("Select a matching run from the same group and storage declaration")
            operations = pin_operation_parents(disposition_operations(boundary, parent, runs, mode), boundary)
        if operations:
            commit_batch(boundary, state, {"mode": mode, "group": group, "context": context,
                                          "manifest": digest(manifest), "operations": operations,
                                          "parent": parent["header"]["run"] if parent else None,
                                          "routes": [rule.get("route", rule["target"]) for rule in rules]}, rsync)
    return actions


def apply(manifest, *, generated=None, rsync=None):
    """Programmatic entry point for an already isolated fixture."""
    result = []
    for group in groups(manifest):
        result.extend(mutate(manifest, "apply", group, generated or {}, rsync, require_token=False))
    return result


def display_actions(actions):
    for action in actions:
        if action["action"] == "move":
            action = {key: value for key, value in action.items() if key != "entry"}
            action["backup"] = "scaffolding" if action["backup"] else None
            action["transfer"] = "rename" if action.pop("sourceMount") == action.pop("targetMount") else "copy"
        yield action


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--rsync", help=argparse.SUPPRESS)
    parser.add_argument("--launcher", help=argparse.SUPPRESS)
    parser.add_argument("mode", choices=["check", "inventory", "plan", "apply", "recover", "retire", "retire-equal", "rollback"],
                        nargs="?", default="check")
    parser.add_argument("--group")
    parser.add_argument("--offline", action="store_true", help="confirm the approved writer-excluded window")
    parser.add_argument("--expect", help="token emitted by plan for this exact apply")
    parser.add_argument("--run", help="journal run ID for recover, retire or rollback")
    parser.add_argument("--retire-equal", action="store_true", help="plan reversible quarantine of matching copies")
    parser.add_argument("--generation")
    parser.add_argument("--previous")
    parser.add_argument("--incumbent", help=argparse.SUPPRESS)
    parser.add_argument("--sessions-active", action="store_true", help=argparse.SUPPRESS)
    checks = parser.add_mutually_exclusive_group()
    checks.add_argument("--require-noop", action="store_true", help="fail if migration work is pending")
    checks.add_argument("--activation", action="store_true", help="protect Home Manager's write boundary")
    checks.add_argument("--admission", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    changing = args.mode in ("apply", "recover", "retire", "retire-equal", "rollback")
    if changing and not (args.group and args.offline):
        parser.error("Mutation requires --group and an approved --offline window")
    if args.mode in ("recover", "retire", "rollback") and not args.run:
        parser.error("Select a journal with --run")
    if (args.require_noop or args.activation or args.admission) and args.mode != "check":
        parser.error("Check flags are only valid with check")
    if args.mode == "plan" and not args.group:
        parser.error("Select a group with --group")
    if args.retire_equal and args.mode != "plan":
        parser.error("--retire-equal requires plan")
    try:
        manifest = json.loads(args.manifest.read_text())
        home, state = manifest_paths(manifest)
        boundary = MoveBoundary()
        generation = generation_path(args.generation)
        if args.generation and generation is None:
            raise Unsupported("Candidate Home Manager generation is unavailable")
        if generation is None and args.launcher:
            parent = Path(args.launcher).absolute().parent
            if (parent / "home-files").exists():
                generation = generation_path(parent)
        if generation and manifest.get("version") == 2:
            declared = (generation / "home-layout-manifest.json").resolve(strict=True)
            if declared != args.manifest.resolve(strict=True):
                raise Unsupported("The runner and candidate generation have different declarations")
        previous = generation_path(args.previous)
        incumbent = generation_path(args.incumbent) if args.admission else previous
        if args.admission or args.activation:
            activation_gate(manifest, boundary, generation, previous, incumbent, args.sessions_active)
            return 0
        generated = generation_files(home, generation)
        active = active_generations(home, manifest.get("stateHome"))
        if previous and previous not in active:
            raise Unsupported("The supplied previous generation is absent from the active Home Manager GC roots")
        merge_generation_files(generated, home, active)
        if args.mode == "inventory":
            subset = {**manifest, "rules": groups(manifest)[args.group]} if args.group else manifest
            print(json.dumps(inspect_routes(subset, boundary, generated), indent=2))
            return 0
        if changing:
            actions = mutate(manifest, args.mode, args.group, generated, args.rsync,
                             expect=args.expect, run_id=args.run)
        elif args.mode == "plan":
            operation = "retire-equal" if args.retire_equal else "apply"
            runs = read_runs(boundary, state)
            if unfinished := [run for run in runs if not run["finished"]]:
                raise Conflict(f"Recover outstanding run: {unfinished[0]['path']}")
            if not args.retire_equal and verified_transfer(manifest, args.group, runs, boundary,
                                                           unchanged=True, retained_only=True):
                actions, operations = [], []
            else:
                actions, operations = plan_group(manifest, args.group, boundary, generated, retire_equal=args.retire_equal)
            print(json.dumps({"group": args.group, "context": run_context(manifest, args.group),
                              "operation": operation,
                              "actions": list(display_actions(actions)),
                              "transfers": [{"kind": op["kind"], "source": op["source"], "target": op["target"],
                                             "mounts": [op["left"], op["right"]], "sibling": op.get("sibling")}
                                            for op in operations],
                              "expect": authority(manifest, args.group, operations, operation) if operations else None},
                             indent=2))
            return 0
        else:
            runs = read_runs(boundary, state)
            unfinished = [run for run in runs if not run["finished"]]
            if unfinished:
                raise Conflict(f"Recover outstanding run: {unfinished[0]['path']}")
            selected_groups = [args.group] if args.group else groups(manifest)
            subset = {**manifest, "rules": [
                rule for group in selected_groups
                if not verified_transfer(manifest, group, runs, boundary, unchanged=True, retained_only=True)
                for rule in groups(manifest)[group]
            ]}
            actions = plan(subset, boundary, compare_collisions=True, generated=generated)
    except subprocess.CalledProcessError as error:
        print(f"home migration stopped: staged copy failed (rsync exit {error.returncode}); preserve the journal",
              file=sys.stderr)
        return 1
    except (Conflict, OSError, ValueError, KeyError, TypeError) as error:
        print(f"home migration stopped ({type(error).__name__}): {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("home migration interrupted; preserve any journal and staging", file=sys.stderr)
        return 130
    print(json.dumps(list(display_actions(actions)), ensure_ascii=False, indent=2))
    if any(action["action"] != "move" for action in actions):
        print("home migration needs operator review; apply refuses existing entries requiring repair", file=sys.stderr)
    if args.require_noop and actions:
        print("home migration pending: activation blocked before writes", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
