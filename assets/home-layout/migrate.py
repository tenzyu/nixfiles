"""Home Manager's Linux XDG migration. Check is read-only; apply never merges data."""

import argparse
from contextlib import contextmanager
from dataclasses import dataclass, replace
import datetime
from enum import Enum, auto
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


@dataclass(frozen=True)
class Publication:
    source: Path
    target: Path
    retained: bool = False
    mount: str | None = None


@dataclass(frozen=True)
class PathProjection:
    """Read a future namespace through an ordered set of allowed publications."""

    moves: tuple[Publication, ...] = ()

    def after(self, move):
        return PathProjection((*self.moves, move))

    def lookup(self, path):
        mount = None
        for move in reversed(self.moves):
            if path.is_relative_to(move.target):
                path = move.source / path.relative_to(move.target)
                mount = mount or move.mount
            elif not move.retained and path.is_relative_to(move.source):
                return None, None
        return path, mount

    def redirect(self, path):
        """The intended home of a legacy reference, following the deepest claim."""
        for move in sorted(self.moves, key=lambda move: -len(move.source.parts)):
            if path.is_relative_to(move.source):
                if move.source != move.target:
                    return move.target / path.relative_to(move.source)
                return None
        return None

    def parent(self, boundary, path, *, expected_mount=None):
        while True:
            actual, mount = self.lookup(path)
            if actual is not None:
                try:
                    with boundary.directory(actual) as fd:
                        actual_mount = boundary.mount(fd, actual)
                        if expected_mount is not None and (mount or actual_mount) != expected_mount:
                            raise Conflict(f"Mount changed after planning: {path}")
                        boundary.writable(fd, actual)
                        return actual, mount or actual_mount
                except FileNotFoundError:
                    pass
            if path == path.parent:
                raise Conflict("Migration destination has no available parent")
            path = path.parent


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


def relocated_absolute(value, routes):
    return routes.redirect(Path(os.path.normpath(value))) if os.path.isabs(value) else None


def link_repairs(root, destination, routes, excluded=()):
    """Plan link changes, including resumption after a successful directory rename."""
    actions = []
    for link in tree(root, excluded):
        if not link.is_symlink():
            continue
        original = os.readlink(link)
        relocated = relocated_absolute(original, routes)
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


@dataclass(frozen=True)
class RouteMember:
    source: Path
    target: Path
    selected: Path


@dataclass(frozen=True)
class GroupPaths:
    """All consumer paths, including fixed claims inside movable roots."""

    members: tuple[RouteMember, ...]
    fixed: frozenset[Path]

    @classmethod
    def from_rules(cls, rules):
        return cls(tuple(RouteMember(absolute(rule["source"]), absolute(rule["target"]),
                                     absolute(rule.get("route", rule["target"]))) for rule in rules),
                   frozenset(absolute(path) for rule in rules
                             for path in rule.get("independentRoutes", {}).values()))

    @property
    def roots(self):
        return self.fixed | {path for member in self.members
                             for path in (member.source, member.target, member.selected)}

    @property
    def redirects(self):
        return PathProjection(tuple(Publication(path, path) for path in sorted(self.fixed))
                              + tuple(Publication(member.source, member.target) for member in self.members))

    def regions(self, boundary, root, covered=(), projection=PathProjection(), carriers=()):
        """Largest regions left after subtracting fixed and already covered claims."""
        excluded = self.fixed.union(covered)

        def descend(path):
            if any(path.is_relative_to(claim) for claim in excluded):
                return
            if path not in carriers and not any(claim.is_relative_to(path) for claim in excluded):
                yield path
                return
            actual, _ = projection.lookup(path)
            if actual is None:
                return
            try:
                with boundary.directory(actual) as directory:
                    names = sorted(os.listdir(directory))
            except FileNotFoundError:
                return
            for name in names:
                yield from descend(path / name)

        return tuple(descend(root))

    def state(self, boundary, root, generated, *, covered=(), projection=PathProjection(), carriers=()):
        try:
            states = {route_state(boundary, actual, generated)
                      for path in self.regions(boundary, root, covered, projection,
                                               self.source_carriers(root).union(carriers))
                      if (actual := projection.lookup(path)[0]) is not None}
        except (Conflict, OSError):
            return "unknown"
        return next((state for state in ("data", "scaffold") if state in states), "absent")

    def uncovered(self, boundary, roots, generated, *, covered=(), projection=PathProjection(), carriers=()):
        return tuple(path for path in roots
                     if self.state(boundary, path, generated, covered=covered,
                                   projection=projection, carriers=carriers) in ("data", "unknown"))

    @property
    def legacy(self):
        return tuple(member.source for member in self.members if member.source != member.target)

    @property
    def intended(self):
        return tuple(member.target for member in self.members if member.source != member.target)

    def allows_transfer(self, source, target):
        return (self.redirects.redirect(source) == target
                and not any(overlaps(root, path) for root in (source, target) for path in self.fixed))

    def source_carriers(self, root):
        # A target-side fixed branch also sets subdivision points in the source.
        return {parent for member in self.members if member.source == root
                for claim in self.fixed if claim != member.target and claim.is_relative_to(member.target)
                for parent in (root / claim.relative_to(member.target)).parents if parent.is_relative_to(root)}

    def planned_parts(self, boundary, source, target):
        if any(source.is_relative_to(path) or target.is_relative_to(path) for path in self.fixed):
            if boundary.entry(source) is not None:
                raise Unsupported(f"A fixed consumer owns a migration root: {source} -> {target}")
            return
        for part in self.regions(boundary, source, carriers=self.source_carriers(source)):
            destination = target / part.relative_to(source)
            if any(overlaps(destination, path) for path in self.fixed):
                if boundary.entry(part) is not None:
                    raise Conflict(f"Migration would write a fixed consumer path: {destination}")
                continue
            yield part, destination

    def private_parents(self, source, target):
        return [str(min((root for root in roots if path.is_relative_to(root)), key=lambda root: len(root.parts)).parent)
                for path, roots in ((source, self.legacy), (target, self.intended))]


def reference_names(path):
    """Visit each name a link lookup depends on, including intermediate aliases."""
    pending = list(reversed(path.parts[1:]))
    current = Path("/")
    followed = 0
    while pending:
        component = pending.pop()
        if component == "..":
            current = current.parent
            continue
        current /= component
        yield current
        try:
            info = current.lstat()
        except (FileNotFoundError, NotADirectoryError):
            return
        if stat.S_ISLNK(info.st_mode):
            followed += 1
            if followed > 40:  # Linux cannot resolve the existing link chain.
                return
            target = Path(os.readlink(current))
            current = Path("/") if target.is_absolute() else current.parent
            pending.extend(reversed(target.parts[1:] if target.is_absolute() else target.parts))


def check_fixed_links(boundary, scope, sources):
    if not sources:
        return
    for path in sorted(scope.fixed):
        info = boundary.entry(path)
        if info is None or not stat.S_ISDIR(info.st_mode):
            continue
        boundary.reject_mounts(path)
        for entry in tree(path):
            if entry.is_symlink() and any(name.is_relative_to(source) for name in reference_names(entry)
                                          for source in sources):
                raise Conflict(f"Fixed consumer link depends on a moved path: {entry}")


@dataclass(frozen=True)
class TransferMember:
    index: int
    source: Path
    target: Path
    copied: bool
    equal: bool

    @classmethod
    def from_operations(cls, operations):
        return tuple(cls(index, Path(op["source"]),
                         Path(op["proof"]["target"] if op["kind"] == "equal-retirement" else op["target"]),
                         op["op"] == "copy", op["kind"] == "equal-retirement")
                     for index, op in enumerate(operations) if op["kind"] != "scaffold")


@dataclass(frozen=True)
class ConsumerCoverage:
    legacy: frozenset[Path]
    intended: frozenset[Path]
    carriers: frozenset[Path]

    @classmethod
    def after(cls, members, *, restored=False, retired=False, scaffolds=()):
        return cls(
            frozenset(member.source for member in members if restored or (member.copied and not retired)),
            frozenset(member.target for member in members if not restored or member.equal).union(scaffolds),
            frozenset(parent for member in members if restored and not member.equal for parent in member.target.parents),
        )

    def uncovered(self, scope, boundary, generated, *, projection=PathProjection(), intended=True):
        legacy = scope.uncovered(boundary, scope.legacy, generated, covered=self.legacy, projection=projection)
        if not intended:
            return legacy
        return legacy + scope.uncovered(boundary, scope.intended, generated, covered=self.intended,
                                        projection=projection, carriers=self.carriers)


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
            if (group != earlier_group and any(overlaps(left, right)
                                               for left in protected_roots([rule])
                                               for right in protected_roots([earlier_rule]))):
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


def check_journal_storage(boundary, fd, path):
    mount = boundary.mount(fd, path)
    if boundary.mounts[mount][-1] == "tmpfs":
        raise Unsupported(f"Migration journal needs durable storage: {path}")
    boundary.writable(fd, path)


def check_state(boundary, state):
    with boundary.directory(state, nearest=True) as fd:
        check_journal_storage(boundary, fd, state)
        if exists(state):
            info = os.fstat(fd)
            if info.st_uid != boundary.uid or info.st_mode & 0o077:
                raise Unsupported(f"Migration state must be private and owned by the HOME owner: {state}")


def journal_state(state_home):
    return state_home / "home-cleanup/bronze/activation"


def declared_states(manifest):
    return {absolute(manifest["state"]),
            *(journal_state(absolute(base)) for base in manifest.get("legacyStateHomes", []))}


def generation_manifests(home, generations):
    for generation in sorted(generations):
        path = generation / "home-layout-manifest.json"
        if path.is_file():
            manifest = json.loads(path.read_text())
            if manifest["home"] != str(home):
                raise Unsupported("The Home Manager generation has a different HOME")
            yield manifest


@dataclass(frozen=True)
class JournalDomain:
    """Stable HOME-relative discovery for journals that stay in their v2 directories."""

    locator: Path
    primary: Path
    locations: tuple[Path, ...]
    recorded: tuple[Path, ...]

    @staticmethod
    def address(home):
        return home / ".home-layout-journal-domain.json"

    @classmethod
    def discover(cls, boundary, manifest, *previous):
        home, declared = manifest_paths(manifest)
        default = journal_state(home / ".local/state")
        locator = cls.address(home)
        recorded = ()
        if boundary.entry(locator) is not None:
            with boundary.directory(locator.parent) as directory:
                fd = os.open(locator.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
                with os.fdopen(fd, encoding="utf-8") as stream:
                    info = os.fstat(stream.fileno())
                    if (not stat.S_ISREG(info.st_mode) or info.st_uid != boundary.uid
                            or info.st_mode & 0o077 or info.st_nlink != 1):
                        raise Unsupported(f"Untrusted migration journal domain: {locator}")
                    record = json.load(stream)
            recorded = tuple(absolute(path) for path in record["locations"])
            if record["version"] != 1 or not recorded or len(set(recorded)) != len(recorded):
                raise Conflict(f"Preserve and review the migration journal domain: {locator}")
        candidates = {declared, *recorded}
        claims = set()
        for declaration in (manifest, *previous):
            candidates.update(declared_states(declaration))
            claims.update(protected_roots(declaration["rules"]))
        for path in (*candidates, default, locator):
            if (home.is_relative_to(path) or any(overlaps(path, claim) for claim in claims)
                    or (path != locator and overlaps(path, locator))):
                raise Unsupported(f"Journal discovery overlaps a protected path: {path}")
        present = {path for path in candidates if boundary.entry(path) is not None}
        if default not in candidates:
            try:
                if boundary.entry(default) is not None:
                    present.add(default)
            except Unsupported:
                # An unused conventional symlink is not a writable v2 domain.
                # If it still reaches a journal directory, require diagnosis.
                if default.resolve() == default or exists(default):
                    raise
        missing = set(recorded) - present
        if missing:
            raise Conflict(f"A recorded migration journal directory is unavailable: {min(missing)}")
        primary = recorded[0] if recorded else declared
        return cls(locator, primary, (primary, *sorted(present - {primary})), recorded)

    def runs(self, boundary):
        runs = [run for location in self.locations for run in read_runs(boundary, location)]
        if len({run["header"]["run"] for run in runs}) != len(runs):
            raise Conflict("Duplicate migration run IDs in the journal domain")
        return sorted(runs, key=lambda run: run["header"]["run"])

    def bind(self, boundary):
        # Called under the HOME inode flock, before the durable begin.
        if self.locations == self.recorded:
            return
        with boundary.directory(self.locator.parent) as directory:
            check_journal_storage(boundary, directory, self.locator)
            with boundary.directory(self.primary, create=True):
                pass
            temporary = f".{self.locator.name}-{uuid.uuid4().hex}"
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            fd = os.open(temporary, flags, 0o600, dir_fd=directory)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump({"version": 1, "locations": list(map(str, self.locations))}, stream)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.locator.name, src_dir_fd=directory, dst_dir_fd=directory)
            os.fsync(directory)


def check_journal_handoff(boundary, manifest, previous, recorded):
    inherited = set().union(*(declared_states(old) for old in previous))
    retained = declared_states(manifest) | {journal_state(Path(manifest["home"]) / ".local/state"), *recorded}
    for location in sorted(inherited - retained):
        if boundary.entry(location) is None:
            continue
        with boundary.directory(location) as directory:
            if os.listdir(directory):
                raise Conflict(f"Keep historical journals discoverable through legacyStateHomes: {location}")


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


def planned_rules(manifest, boundary, scope):
    for rule in manifest["rules"]:
        source, target = absolute(rule["source"]), absolute(rule["target"])
        owner = rule["owner"]
        if not isinstance(owner, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", owner):
            raise Unsupported("Migration rule requires a valid feature owner")
        home = absolute(manifest["home"])
        if not source.is_relative_to(home) or source == home:
            raise Conflict(f"Source must be below HOME: {source}")
        if source == target:
            continue
        for part, destination in scope.planned_parts(boundary, source, target):
            if part != source and rule.get("references"):
                raise Unsupported(f"Splitting a root with legacy references requires operator review: {source}")
            yield rule, part, destination


def plan(manifest, boundary=None, *, activation=False, compare_collisions=False, generated=None, state=None):
    home, declared = manifest_paths(manifest)
    boundary = boundary or MoveBoundary()
    scope = GroupPaths.from_rules(manifest["rules"])
    redirects = scope.redirects
    projection = PathProjection()
    actions, patterns = [], []
    generated = generated or {}
    managed_paths = set(generated) if generated else set(map(absolute, manifest.get("managed", [])))
    for rule, source, target in planned_rules(manifest, boundary, scope):
        owner = rule["owner"]
        actual_source, _ = projection.lookup(source)
        actual_target, _ = projection.lookup(target)
        source_info = boundary.entry(actual_source) if actual_source is not None else None
        if source_info is not None:
            resolve_external(boundary, manifest, target)
            source_entry = identity(source_info)
            if source_entry[2] not in (stat.S_IFDIR, stat.S_IFREG):
                raise Conflict(f"Unsupported legacy file type: {source}")
            _, target_mount = projection.parent(boundary, target.parent)
            with boundary.directory(actual_source.parent) as left:
                source_mount = boundary.mount(left, actual_source.parent)
                boundary.writable(left, actual_source.parent)
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
            detached = [move.source for move in projection.moves if not move.retained]
            if source_entry[2] == stat.S_IFDIR:
                for link in tree(actual_source, detached):
                    if not link.is_symlink():
                        continue
                    value = os.readlink(link)
                    if relocated_absolute(value, redirects) is not None:
                        if not rule.get("repairAbsoluteLinks", False):
                            raise Conflict(f"Absolute legacy-root symlink requires repair: {link}")
                    if not os.path.isabs(value):
                        # A relative link to another copied member remains valid,
                        # including cargo -> rustup -> /nix/store/... chains.
                        lexical = Path(os.path.abspath(link.parent / value))
                        if lexical.is_relative_to(actual_source):
                            translated = relocated_absolute(str(lexical), redirects)
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
            action = {"action": "move", "source": str(source), "target": str(target),
                      "owner": owner, "entry": source_entry, "backup": backup,
                      "sourceMount": source_mount, "targetMount": target_mount,
                      "observedTarget": actual_target}
            parents = scope.private_parents(source, target)
            if parents != [str(source.parent), str(target.parent)]:
                # Keep private stages and quarantines outside a protected carrier.
                action["privateParents"] = parents
            actions.append(action)
            projection = projection.after(Publication(source, target, source_mount != target_mount, target_mount))
            patterns.extend(rule.get("processes", []))
            if rule.get("repairAbsoluteLinks", False) and source_entry[2] == stat.S_IFDIR:
                actions.extend({**repair, "owner": owner, "legacy": str(source), "root": str(target)}
                               for repair in link_repairs(actual_source, target, redirects, detached))
        elif (rule.get("repairAbsoluteLinks", False) and actual_target is not None
              and (info := boundary.entry(actual_target)) is not None and stat.S_ISDIR(info.st_mode)):
            # Diagnose legacy links even if an earlier version already moved the tree.
            with boundary.directory(actual_target):
                pass
            boundary.reject_mounts(actual_target)
            repairs = link_repairs(actual_target, target, redirects)
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
            actual, _ = projection.lookup(dest)
            if actual is None or boundary.entry(actual) is None:
                continue
            with boundary.directory(actual.parent):
                if not (actual.is_file() and (not actual.is_symlink() or store_link(actual))):
                    raise Conflict(f"Unknown reference file type: {actual}")
                if check_reference(actual, dest, source, target, home):
                    actions.append({"action": "rewrite", "current": str(actual), "target": str(dest),
                                    "legacy": str(source), "root": str(target), "owner": owner})
                    patterns.extend(rule.get("processes", []))
    if projection.moves:
        check_fixed_links(boundary, scope, tuple(move.source for move in projection.moves))
        check_state(boundary, state or declared)
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
    return GroupPaths.from_rules(rules).roots


def check_cleanup_parents(boundary, home, removed, previous, roots):
    # Native HM unlinks orphaned generation leaves, then runs rmdir -p.
    # Test the children remaining after all such unlinks, from the bottom up.
    parents = {parent for path in removed for parent in path.parents
               if parent != home and parent.is_relative_to(home)}
    for parent in sorted(parents, key=lambda path: (-len(path.parts), path)):
        with boundary.directory(parent) as directory:
            if any(parent / name not in removed for name in os.listdir(directory)):
                continue
        if any(parent.is_relative_to(root) for root in roots) and not generated_tree(parent, previous):
            raise Conflict(f"Home Manager cleanup would remove a protected directory: {parent}")
        removed.add(parent)


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
    removed = set()
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
        if (path in previous and stat.S_ISLNK(info.st_mode)
                and re.match(r"/nix/store/[^/]+-home-manager-files/", os.readlink(path))
                and not any(Path(leaf).exists() for leaf in candidate.get(path, ()))
                and not any(leaf != path and leaf.is_relative_to(path) for leaf in candidate)):
            if any(overlaps(path, root) for root in roots) and not owned_link(path, previous):
                raise Conflict(f"Home Manager cleanup could remove an unproven protected link: {path}")
            removed.add(path)
    check_cleanup_parents(boundary, absolute(manifest["home"]), removed, previous, roots)
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
    home, _ = manifest_paths(manifest)
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
    old_generations = active_generations(home, manifest.get("stateHome"), old_manifest.get("stateHome"),
                                         *manifest.get("legacyStateHomes", []), *old_manifest.get("legacyStateHomes", []))
    old_generations.update(path for path in (previous, incumbent) if path)
    old_files = {}
    merge_generation_files(old_files, home, old_generations)

    default = journal_state(home / ".local/state")
    roots = {*protected_roots(manifest["rules"] + old_manifest.get("rules", [])),
             default, JournalDomain.address(home)}
    declarations = tuple(generation_manifests(home, old_generations))
    for declaration in (manifest, *declarations):
        roots.update(declared_states(declaration))
    domain = None
    try:
        domain = JournalDomain.discover(boundary, manifest, *declarations)
        roots.update(domain.locations)
        runs = domain.runs(boundary)
        journals_known = True
    except (Conflict, OSError, ValueError, KeyError, TypeError) as error:
        print(f"Home migration journals need review: {error}", file=sys.stderr)
        runs = []
        journals_known = False
    check_journal_handoff(boundary, manifest, declarations, domain.recorded if domain else ())
    generated = project_writes(manifest, boundary, generation_files(home, generation), old_files, roots)
    print("Home migration activation writes: safe for protected roots", file=sys.stderr)
    for group, rules in old.items():
        if group not in current:
            if not journals_known or any(run["header"]["group"] == group and not run["finished"] for run in runs):
                raise Conflict(f"[{group}] runtime continuity: resolve migration history before removing a route")
            if any(route_state(boundary, path, generated) == "data" for path in protected_roots(rules)):
                raise Conflict(f"[{group}] runtime continuity: removing a route with existing data")

    for group, rules in current.items():
        incumbent_rules = old.get(group, [])
        scope = GroupPaths.from_rules(rules)
        selected = [member.selected for member in scope.members]
        legacy = [member.source for member in scope.members]
        intended = [member.target for member in scope.members]
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
            removed = [rule for path, rule in before.items() if absolute(path) not in legacy]
            if any(assess_root(boundary, path, generated) in ("data", "unknown")
                   for path in protected_roots(removed)):
                raise Conflict(f"[{group}] runtime continuity: removing a consumer with existing data")
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
        source_states = [scope.state(boundary, path, generated) for path in legacy]
        target_states = [scope.state(boundary, path, generated) for path in intended]
        incumbent_only = protected_roots(incumbent_rules) - scope.roots
        incumbent_states = {assess_root(boundary, path, generated) for path in incumbent_only}
        data = {"data", "unknown"}
        has_old = any(state in data and source != target
                      for state, source, target in zip(source_states, legacy, intended))
        has_new = bool(data.intersection(target_states))
        independent_states = {assess_root(boundary, path, generated) for path in scope.fixed}
        incumbent_pending = bool(data.intersection(incumbent_states))
        if "unknown" in independent_states:
            raise Conflict(f"[{group}] runtime continuity: unsafe independent consumer root")
        selected_states = source_states if held else target_states
        if "unknown" in selected_states:
            raise Conflict(f"[{group}] runtime continuity: unsafe selected root")
        same_installed_route = group in old and old_routes == selected
        # With unavailable history, only independently observed records on
        # every installed held route can establish continuity.
        if not journals_known and not (
            held and same_installed_route and set(selected_states).union(independent_states) == {"data"}
        ):
            raise Conflict(f"[{group}] runtime continuity: resolve migration history before routing")

        transfers = completed_transfers(manifest, group, runs, same_rules=False)
        pending = has_old or has_new or incumbent_pending or bool(transfers)
        if incumbent_pending:
            assessment = "incumbent roots outside the candidate require assessment"
        elif has_old and has_new:
            assessment = "both locations need assessment"
        elif transfers and not (has_old or has_new):
            assessment = "recorded publication needs assessment"
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
                if not verified_rollback(manifest, group, runs, boundary, generated):
                    raise Conflict(f"[{group}] runtime continuity: legacy route requires a verified rollback")
            elif pending and (old_routes != selected or not selected_has_data):
                raise Conflict(f"[{group}] runtime continuity: no verified legacy incumbent")
            if any(new == "data" and prior != "data" for prior, new in zip(source_states, target_states)):
                raise Conflict(f"[{group}] runtime continuity: legacy route would expose an incomplete group")
        else:
            changed = old_routes is not None and selected != old_routes
            selected_history = tuple(run for run in transfers if touches_intended_route(scope, run))
            if changed and pending:
                if sessions_active:
                    raise Conflict(f"[{group}] runtime continuity: exclude active sessions and writers before cutover")
                reconciled = (group in manifest.get("reconciled", []) and not incumbent_pending
                              and not has_old and has_new
                              and not plan({**manifest, "rules": rules}, boundary, activation=True,
                                           generated=generated))
                scoped = tuple(run for run in transfers if matches_run(manifest, group, run))
                if not (reconciled or (old_routes == legacy and not incumbent_pending
                                       and verify_transfer(scope, scoped, runs, boundary, generated))):
                    raise Conflict(f"[{group}] runtime continuity: intended route requires a verified transfer")
            elif has_old or selected_history:
                # An unchanged intended route may already be split. Do not
                # start more writers against an unresolved target.
                if not verify_transfer(scope, selected_history, runs, boundary, generated,
                                       unchanged=same_installed_route):
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


def run_context(manifest, group, state=None):
    # The completed transfer also applies to the generation selecting the
    # other route. Moving roots or changing reference policy invalidates it.
    rules = [{k: v for k, v in rule.items() if k not in ("route", "consumers", "serviceRoutes")}
             for rule in groups(manifest)[group]]
    return {"host": manifest.get("host") or socket.gethostname(), "machine": socket.gethostname(),
            "uid": os.geteuid(), "home": manifest["home"],
            "state": str(state) if state is not None else manifest["state"],
            "rules": digest(rules)}


def matches_run(manifest, group, run, *, same_rules=True):
    header = run["header"]
    expected = run_context(manifest, group, run["path"].parent)
    current = header["context"]
    if not same_rules:
        expected["rules"] = current.get("rules")
    return header["group"] == group and current == expected


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


@dataclass(frozen=True)
class StepEvidence:
    staging: Path | None = None
    ready: tuple[Path, tuple[int, ...]] | None = None
    intended: bool = False
    done: tuple[int, ...] | None = None


def journal_prefix(header, events):
    """Decode the single active step of a v2 journal and its finished prefix."""
    operations = header["operations"]
    steps = [StepEvidence() for _ in operations]
    index = 0
    finished = False
    for event in events:
        kind = event["event"]
        if not finished and kind == "finished" and index == len(operations):
            finished = True
            continue
        if finished or index >= len(operations) or event.get("index") != index:
            raise ValueError("Journal advanced out of order")
        op, step = operations[index], steps[index]
        if kind == "staging" and op["op"] == "copy" and step.ready is None:
            stage = absolute(event["stage"])
            prefix = f".home-layout-{header['run']}-{index}-"
            if (stage.parent != private_parent(op, 1)
                    or not re.fullmatch(re.escape(prefix) + r"[0-9a-f]{12}-stage", stage.name)):
                raise ValueError("Unexpected copy stage")
            steps[index] = replace(step, staging=stage)
        elif kind == "ready" and step.staging is not None and step.ready is None:
            stage = absolute(event["stage"])
            entry = tuple(event["entry"])
            if stage != step.staging / "payload" or len(entry) != 3 or entry[2] != op["entry"][2]:
                raise ValueError("Unexpected ready stage")
            steps[index] = replace(step, ready=(stage, entry))
        elif kind == "intent" and (op["op"] == "rename" or step.ready is not None):
            source, entry = step.ready or (Path(op["source"]), tuple(op["entry"]))
            if (event["source"], event["target"], tuple(event["entry"])) != (str(source), op["target"], entry):
                raise ValueError("Unexpected publication intent")
            steps[index] = replace(step, intended=True)
        elif kind == "done" and step.intended:
            expected = step.ready[1] if step.ready else tuple(op["entry"])
            if tuple(event["entry"]) != expected:
                raise ValueError("Unexpected publication identity")
            steps[index] = replace(step, done=expected)
            index += 1
        else:
            raise ValueError("Unexpected journal event")
    return tuple(steps), finished


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
                lines = log.readlines()
            if any(not line.endswith("\n") for line in lines):
                raise ValueError("Torn migration record")
            events = [json.loads(line) for line in lines]
            for event in events:
                if event.pop("recordHash", None) != digest(event):
                    raise ValueError()
            header = events[0]
            if header.get("version") != 2 or header.get("event") != "begin" or header.get("run") != name:
                raise ValueError()
            steps, finished = journal_prefix(header, events[1:])
        except (FileNotFoundError, ValueError, IndexError, AttributeError, KeyError, TypeError) as error:
            raise Conflict(f"Preserve and review an incomplete or older migration journal: {run}") from error
        result.append({"path": run, "header": header, "events": events[1:], "steps": steps, "finished": finished})
    return result


def approved_operations(actions, boundary):
    operations = []
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
            fingerprint, _ = payload(boundary, action["observedTarget"], right)
            scaffold = {"op": "rename", "kind": "scaffold", "source": str(target),
                        "target": None, "sibling": f"scaffold-{index}", "entry": list(action["backup"]),
                        "left": right, "right": right, "payload": fingerprint,
                        "exclude": [], "targetExclude": [], "mutable": []}
            if "privateParents" in action:
                scaffold["privateParents"] = [action["privateParents"][1]] * 2
            operations.append(scaffold)
        fingerprint, size = payload(boundary, source, left, excludes, mutable, copy=copy)
        op = {"op": "copy" if copy else "rename", "kind": "legacy",
              "source": str(source), "target": str(target), "entry": list(action["entry"]),
              "left": left, "right": right, "payload": fingerprint, "bytes": size,
              "exclude": excludes, "targetExclude": target_excludes, "mutable": mutable}
        if "privateParents" in action:
            op["privateParents"] = action["privateParents"]
        operations.append(op)
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


def check_staging_capacity(boundary, copies):
    storage = {}
    for operation in copies:
        # A projected parent may still be on the source mount. Use the
        # existing destination-side ancestor for the filesystem check.
        path, _, mount = operation["anchors"][1]
        if mount != operation["right"]:
            raise Conflict(f"Destination mount changed after planning: {operation['target']}")
        parent, size = storage.get(mount, (Path(path), 0))
        storage[mount] = (parent, size + operation["bytes"])
    for parent, size in storage.values():
        boundary.check_capacity(parent, size)


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


def private_parent(operation, side):
    if "privateParents" in operation:
        return absolute(operation["privateParents"][side])
    return Path(operation[("source", "target")[side]]).parent


def new_stage(boundary, log, run, index, op, source, target, rsync):
    if not rsync:
        raise Unsupported("Cross-mount transfer requires the packaged rsync")
    parent = private_parent(op, 1)
    boundary.check_capacity(parent, op["bytes"])
    stage = parent / f".home-layout-{run.name}-{index}-{uuid.uuid4().hex[:12]}-stage"
    write_journal(log, {"event": "staging", "index": index, "stage": str(stage)})
    with boundary.directory(stage.parent, create=True) as parent_fd:
        if boundary.mount(parent_fd, target) != op["right"]:
            raise Conflict(f"Destination mount changed before staging: {target}")
        os.mkdir(stage.name, mode=0o700, dir_fd=parent_fd)
        os.fsync(parent_fd)
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


class PublicationState(Enum):
    NEEDS_STAGE = auto()
    READY = auto()
    PUBLISHED = auto()


@dataclass(frozen=True)
class PublicationCheck:
    state: PublicationState
    source: Path
    entry: tuple[int, ...]


def classify_publication(boundary, op, evidence, projection, *, rsync, sync=False):
    """Check a pending effect at its projected address or at the live boundary."""
    source, target = Path(op["source"]), Path(op["target"])
    observed_source, source_mount = projection.lookup(source)
    if source_mount is not None and source_mount != op["left"]:
        raise Conflict(f"Mount changed after planning: {source}")
    before = observe(boundary, observed_source, op["left"]) if observed_source is not None else None
    if projection.moves:
        actual, _ = projection.lookup(target)
        info = boundary.entry(actual) if actual is not None else None
        after = list(identity(info)) if info is not None else None
    else:
        after = observe(boundary, target, op["right"])

    copy = op["op"] == "copy"
    if copy:
        if before != op["entry"]:
            raise Conflict(f"Copy source changed after planning: {source}")
        check_payload(boundary, op, observed_source)
        if evidence.ready is None:
            if after is not None:
                raise Conflict(f"Copy target is already occupied: {target}")
            if not rsync:
                raise Unsupported("Cross-mount transfer requires the packaged rsync")
            projection.parent(boundary, target.parent, expected_mount=op["right"])
            return PublicationCheck(PublicationState.NEEDS_STAGE, source, tuple(op["entry"]))

    move_from, entry = evidence.ready or (source, tuple(op["entry"]))
    staged = observe(boundary, move_from, op["right"]) if copy else before
    if after is not None:
        if not evidence.intended or after != list(entry) or staged is not None:
            raise Conflict(f"Cannot reconcile existing destination without replacing data: {target}")
        check_payload(boundary, op, target, target=True, sync=sync)
        with boundary.directory(move_from.parent):
            pass  # Recovery must still be able to reflush both parents.
        return PublicationCheck(PublicationState.PUBLISHED, move_from, entry)

    if staged != list(entry):
        raise Conflict(f"Migration source changed or is missing: {move_from}")
    actual = move_from if copy else observed_source
    check_payload(boundary, op, actual, target=copy, sync=sync)
    with boundary.directory(actual.parent) as left:
        boundary.writable(left, actual.parent)
    projection.parent(boundary, target.parent, expected_mount=op["right"])
    return PublicationCheck(PublicationState.READY, move_from, entry)


def execute_operation(boundary, log, run, index, op, evidence, rsync):
    target = Path(op["target"])
    current = classify_publication(boundary, op, evidence, PathProjection(), rsync=rsync, sync=True)
    if current.state is PublicationState.NEEDS_STAGE:
        ready = new_stage(boundary, log, run, index, op, current.source, target, rsync)
        evidence = replace(evidence, ready=(Path(ready["stage"]), tuple(ready["entry"])))
        current = classify_publication(boundary, op, evidence, PathProjection(), rsync=rsync, sync=True)
    move_from, entry = current.source, list(current.entry)
    if current.state is PublicationState.PUBLISHED:
        with boundary.directory(move_from.parent) as left:
            os.fsync(left)
    else:
        write_journal(log, {"event": "intent", "index": index, "source": str(move_from),
                            "target": str(target), "entry": entry})
        if proof := op.get("proof"):
            verify_authoritative(boundary, op, proof)
        commit_move(boundary, move_from, target, entry, op["right"])
    write_journal(log, {"event": "done", "index": index, "entry": entry})


def check_completed_operation(boundary, operation, complete, replacement):
    target = Path(operation["target"])
    if observe(boundary, target, operation["right"]) != list(complete):
        raise Conflict(f"Earlier committed step changed before recovery: {target}")
    check_payload(boundary, operation, target, target=True)
    if operation["kind"] != "scaffold":
        source = Path(operation["source"])
        remaining = observe(boundary, source, operation["left"])
        if operation["op"] == "copy" and remaining == operation["entry"]:
            check_payload(boundary, operation, source)
        elif (remaining is not None and remaining != replacement) or operation["op"] == "copy":
            raise Conflict(f"Earlier committed step has an unexpected legacy entry: {source}")


def preflight_run(boundary, journal, rsync, scope, generated, history):
    operations = journal["header"]["operations"]
    steps = journal["steps"]
    intents = {op["target"]: (index, list(step.ready[1]) if step.ready else op["entry"])
               for index, (op, step) in enumerate(zip(operations, steps)) if step.intended}
    projection = PathProjection()
    unstaged_copies = []
    preflight = []
    for index, (operation, evidence) in enumerate(zip(operations, steps)):
        for anchor in operation["anchors"]:
            if boundary.anchor(Path(anchor[0])) != anchor:
                raise Conflict(f"Planned parent or mount changed: {anchor[0]}")
        if proof := operation.get("proof"):
            verify_authoritative(boundary, operation, proof)
        later_index, entry = intents.get(operation["source"], (-1, None))
        replacement = entry if later_index > index else None
        if evidence.done is not None:
            check_completed_operation(boundary, operation, evidence.done, replacement)
        else:
            current = classify_publication(boundary, operation, evidence, projection, rsync=rsync)
            if current.state is PublicationState.NEEDS_STAGE:
                unstaged_copies.append(operation)
            if current.state is not PublicationState.PUBLISHED:
                projection = projection.after(Publication(
                    current.source, Path(operation["target"]),
                    current.state is PublicationState.NEEDS_STAGE, operation["right"]))
        preflight.append((operation, evidence, replacement))
    check_staging_capacity(boundary, unstaged_copies)
    check_run_coverage(boundary, journal["header"], scope, generated, history, projection)
    return preflight


def execute_run(boundary, journal, log, rsync, scope, generated, history, *, prepared=None, domain=None):
    steps = prepared if prepared is not None else preflight_run(boundary, journal, rsync, scope, generated, history)
    if domain is not None:
        domain.bind(boundary)
    for index, (operation, evidence, replacement) in enumerate(steps):
        if evidence.done is None:
            execute_operation(boundary, log, journal["path"], index, operation, evidence, rsync)
        else:
            check_completed_operation(boundary, operation, evidence.done, replacement)
    check_run_coverage(boundary, journal["header"], scope, generated, history, PathProjection())
    write_journal(log, {"event": "finished"})


def quarantine_target(run, operation):
    return str(private_parent(operation, 0) / f".home-layout-{run}-{operation['sibling']}/payload")


def commit_batch(boundary, domain, state, header, rsync, scope, generated, history):
    name = datetime.datetime.now().strftime("%Y%m%dT%H%M%S-") + uuid.uuid4().hex
    run = state / name
    header = {"event": "begin", "version": 2, "run": name, **header}
    header["operations"] = [
        {**op, "target": op["target"] or quarantine_target(name, op)}
        for op in header["operations"]
    ]
    steps, finished = journal_prefix(header, ())
    journal = {"path": run, "header": header, "events": [], "steps": steps, "finished": finished}
    prepared = preflight_run(boundary, journal, rsync, scope, generated, history)
    domain.bind(boundary)
    print(f"Migration journal: {run}", file=sys.stderr, flush=True)
    with boundary.directory(state, create=True) as parent:
        os.mkdir(name, mode=0o700, dir_fd=parent)
        os.fsync(parent)
        with boundary.directory(run) as directory:
            fd = os.open("operations.jsonl", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=directory)
            with os.fdopen(fd, "w", encoding="utf-8") as log:
                os.fsync(directory)
                write_journal(log, header)
                execute_run(boundary, journal, log, rsync, scope, generated, history, prepared=prepared)


def done_entry(run, index):
    entry = run["steps"][index].done
    return list(entry) if entry is not None else None


def disposition(runs, parent, mode, ancestors=frozenset()):
    parent_id = parent["header"]["run"]
    if parent_id in ancestors:
        raise Conflict("Cyclic migration dispositions")
    active = [run for run in runs
              if run["finished"] and run["header"].get("parent") == parent_id
              and run["header"]["mode"] == mode
              and not disposition(runs, run, "rollback", ancestors | {parent_id})]
    if len(active) > 1:
        raise Conflict(f"Multiple effective {mode} runs for the same migration")
    return active[0] if active else None


def verify_authoritative(boundary, operation, proof, *, unchanged=False, app_save=False):
    target = Path(proof["target"])
    if boundary.mount_at(target.parent) != proof["mount"]:
        raise Conflict(f"Mount changed after planning: {target}")
    info = boundary.entry(target)
    if info is None or list(identity(info)) != proof["entry"]:
        # Only an installed, unchanged route can accept a replacement in a
        # private regular-file slot. It grants no authority over a frozen copy.
        if not (app_save and info and proof["entry"][2] == stat.S_IFREG
                and stat.S_ISREG(info.st_mode) and info.st_uid == boundary.uid
                and not info.st_mode & 0o022 and info.st_nlink == 1):
            raise Conflict(f"Authoritative target identity has changed: {target}")
        boundary.reject_mounts(target)
    if not unchanged:
        fingerprint, _ = payload(boundary, target, proof["mount"], proof.get("exclude", ()),
                                 operation["mutable"], copy=operation["op"] == "copy"
                                 or operation["kind"] != "legacy")
        if fingerprint != operation["payload"]:
            raise Conflict(f"Authoritative target has changed: {target}")


def completed_transfers(manifest, group, runs, *, same_rules=True):
    return tuple(run for run in reversed(runs)
                 if run["finished"] and run["header"]["mode"] in ("apply", "retire-equal")
                 and matches_run(manifest, group, run, same_rules=same_rules)
                 and not disposition(runs, run, "rollback"))


def touches_intended_route(scope, run):
    members = TransferMember.from_operations(run["header"]["operations"])
    return any(overlaps(member.target, root) for member in members for root in scope.intended)


def verify_transfer(scope, transfers, runs, boundary, generated, *, unchanged=False, retained_only=False):
    for run in transfers:
        header = run["header"]
        members = TransferMember.from_operations(header["operations"])
        if not members or any(not scope.allows_transfer(member.source, member.target) for member in members):
            continue
        coverage = ConsumerCoverage.after(members, retired=disposition(runs, run, "retire") is not None)
        if retained_only and not coverage.legacy:
            continue
        try:
            if not retained_only and "fixed" in header:
                check_fixed_continuity(scope, boundary, generated, header["fixed"], unchanged)
            if not (unchanged or retained_only):
                check_fixed_links(boundary, scope, tuple(member.source for member in members))
            for member in members:
                op = header["operations"][member.index]
                proof = op.get("proof") or retirement_proof(run, member.index, op)
                verify_authoritative(boundary, op, proof, unchanged=unchanged or retained_only, app_save=unchanged)
                if member.source in coverage.legacy:
                    if observe(boundary, member.source, op["left"]) != op["entry"]:
                        return False
                    check_payload(boundary, op, member.source)
            return not coverage.uncovered(scope, boundary, generated, intended=not (unchanged or retained_only))
        except (Conflict, OSError):
            return False
    return False


def verified_retained_copy(manifest, group, runs, boundary, generated):
    scope = GroupPaths.from_rules(groups(manifest)[group])
    return verify_transfer(scope, completed_transfers(manifest, group, runs), runs, boundary, generated,
                           retained_only=True)


def verified_rollback(manifest, group, runs, boundary, generated=None):
    scope = GroupPaths.from_rules(groups(manifest)[group])
    for original in reversed(runs):
        header = original["header"]
        if (header["mode"] not in ("apply", "retire-equal")
                or not matches_run(manifest, group, original) or not disposition(runs, original, "rollback")):
            continue
        members = TransferMember.from_operations(header["operations"])
        try:
            check_fixed_links(boundary, scope, tuple(member.target for member in members if not member.equal))
            scaffolds = set()
            for op in header["operations"]:
                if op["kind"] == "scaffold":
                    source = Path(op["source"])
                    if observe(boundary, source, op["left"]) != op["entry"]:
                        return False
                    check_payload(boundary, op, source)
                    scaffolds.add(source)
            for member in members:
                op = header["operations"][member.index]
                if observe(boundary, member.source, op["left"]) != op["entry"]:
                    return False
                check_payload(boundary, op, member.source)
                if proof := op.get("proof"):
                    verify_authoritative(boundary, op, proof)
            coverage = ConsumerCoverage.after(members, restored=True, scaffolds=scaffolds)
            return not coverage.uncovered(scope, boundary, generated or {})
        except (Conflict, OSError):
            return False
    return False


def plan_group(manifest, group, boundary, generated, *, retire_equal=False, state=None):
    subset = {**manifest, "rules": groups(manifest)[group]}
    if retire_equal:
        return [], pin_operation_parents(plan_equal_retirement(subset, boundary), boundary)
    actions = plan(subset, boundary, generated=generated, compare_collisions=True, state=state)
    scope = GroupPaths.from_rules(subset["rules"])
    destinations = {Path(action["target"]) for action in actions if action["action"] == "move"}
    if destinations and scope.uncovered(boundary, scope.intended, generated, covered=destinations):
        raise Conflict(f"[{group}] group is already split; verify an authoritative route before applying")
    operations = []
    if all(action["action"] == "move" for action in actions):
        operations = pin_operation_parents(approved_operations(actions, boundary), boundary)
        check_staging_capacity(boundary, (op for op in operations if op["op"] == "copy"))
    return actions, operations


def authority(manifest, group, operations, mode="apply", *, state=None):
    return digest({"context": run_context(manifest, group, state), "manifest": digest(manifest),
                   "group": group, "operations": operations, "mode": mode})


def plan_equal_retirement(manifest, boundary):
    operations = []
    rules = manifest["rules"]
    scope = GroupPaths.from_rules(rules)
    redirects = scope.redirects
    for index, rule in enumerate(rules):
        source, target = Path(rule["source"]), Path(rule["target"])
        if source == target:
            continue
        if any(overlaps(path, fixed) for path in (source, target) for fixed in scope.fixed):
            raise Unsupported("Matching copies with fixed consumer paths require a topology-specific retirement plan")
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
                    if (relocated_absolute(link, redirects) is not None or
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
    result = {**op, "op": "rename", "kind": kind, "source": str(source),
            "target": str(target) if target is not None else None, "sibling": sibling,
            "entry": entry, "left": mount, "right": mount,
            "exclude": source_exclude, "targetExclude": target_exclude}
    if reverse and "privateParents" in op:
        result["privateParents"] = list(reversed(op["privateParents"]))
    return result


def retirement_sources(parent, runs):
    header = parent["header"]
    if (not parent["finished"] or header["mode"] != "apply"
            or disposition(runs, parent, "rollback") or disposition(runs, parent, "retire")):
        raise Conflict("Retirement requires a completed, unretired transfer")
    return [(index, op) for index, op in enumerate(header["operations"]) if op["op"] == "copy"]


def retirement_proof(parent, index, operation):
    return {"target": operation["target"], "mount": operation["right"],
            "entry": done_entry(parent, index), "exclude": operation["targetExclude"]}


def fixed_witnesses(scope, boundary, generated):
    witnesses = []
    for path in sorted(scope.fixed):
        if assess_root(boundary, path, generated) == "unknown":
            raise Conflict(f"Unsafe fixed consumer path: {path}")
        mount = boundary.mount_at(path.parent)
        witnesses.append([str(path), mount, observe(boundary, path, mount)])
    return witnesses


def check_fixed_continuity(scope, boundary, generated, recorded, unchanged):
    current = fixed_witnesses(scope, boundary, generated)
    for before, after in zip(recorded, current, strict=True):
        path, mount, entry = before
        if after[:2] != [path, mount]:
            raise Conflict(f"Fixed consumer mount changed after publication: {path}")
        if entry is not None:
            found = after[2]
            if found is None or entry[2] != found[2] or (not unchanged and entry != found):
                raise Conflict(f"Fixed consumer path changed after publication: {path}")


def check_run_coverage(boundary, header, scope, generated, history, projection):
    if "fixed" in header and header["fixed"] != fixed_witnesses(scope, boundary, generated):
        raise Conflict("A fixed consumer path changed after planning")
    parent_headers = {run["header"]["run"]: run["header"] for run in history if run["finished"]}
    original, reversed_transfer, retired = header, False, False
    seen = set()
    while original["mode"] in ("rollback", "retire"):
        parent = original.get("parent")
        if parent not in parent_headers or parent in seen:
            raise Conflict("Missing or cyclic migration history")
        seen.add(parent)
        if original["mode"] == "retire":
            retired = not reversed_transfer
            reversed_transfer = False
        else:
            reversed_transfer = not reversed_transfer
        original = parent_headers[parent]

    members = TransferMember.from_operations(original["operations"])
    check_fixed_links(boundary, scope, tuple(Path(op["source"]) for op in header["operations"]))
    for member in members:
        if not reversed_transfer and not scope.allows_transfer(member.source, member.target):
            raise Conflict(f"Transfer conflicts with consumer path ownership: {member.source} -> {member.target}")
    scaffolds = {Path(op["source"]) for op in original["operations"]
                 if reversed_transfer and op["kind"] == "scaffold"}
    coverage = ConsumerCoverage.after(members, restored=reversed_transfer, retired=retired, scaffolds=scaffolds)
    unexpected = coverage.uncovered(scope, boundary, generated, projection=projection)
    if unexpected:
        raise Conflict(f"Unaccounted consumer path in the migration group: {unexpected[0]}")


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
                        target=quarantine_target(header["run"], {**operation, "sibling": sibling}))
        if "privateParents" in operation:
            expected["privateParents"] = operation["privateParents"]
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
    if retired:
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


def mutate(manifest, mode, group, generated, rsync, *, expect=None, run_id=None, require_token=True, previous=()):
    home, _ = manifest_paths(manifest)
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
        scope = GroupPaths.from_rules(rules)
        pids = busy({pattern for rule in rules for pattern in rule.get("processes", [])},
                    protected_roots(rules))
        if pids:
            raise Conflict(f"Close applications before migration (PIDs: {', '.join(pids)})")
        domain = JournalDomain.discover(boundary, manifest, *previous)
        runs = domain.runs(boundary)
        unfinished = [run for run in runs if not run["finished"]]
        if mode == "recover":
            if (len(unfinished) != 1 or unfinished[0]["header"]["run"] != run_id
                    or not matches_run(manifest, group, unfinished[0])
                    or unfinished[0]["header"]["manifest"] != digest(manifest)):
                raise Conflict("Recovery requires the outstanding run, original generation and group")
            journal = unfinished[0]
            if journal["header"]["mode"] == "retire":
                validate_retirement_recovery(journal, runs)
            with journal_data(boundary, journal["path"], append=True) as log:
                execute_run(boundary, journal, log, rsync, scope, generated, runs, domain=domain)
            return []
        if unfinished:
            raise Conflict(f"Recover outstanding run before starting a new one: {unfinished[0]['path']}")
        actions, parent = [], None
        state = domain.primary
        if mode in ("apply", "retire-equal"):
            if mode == "apply" and verified_retained_copy(manifest, group, runs, boundary, generated):
                return []
            actions, operations = plan_group(manifest, group, boundary, generated,
                                             retire_equal=mode == "retire-equal", state=state)
            if any(action["action"] != "move" for action in actions):
                raise Unsupported("Replacement requires exclusive ownership and operator repair; batch refused")
            if operations and require_token and expect != authority(manifest, group, operations, mode, state=state):
                raise Conflict("The plan changed or has no matching --expect token")
        else:
            parent = next((item for item in runs if item["header"]["run"] == run_id
                           and matches_run(manifest, group, item)), None)
            if parent is None:
                raise Conflict("Select a matching run from the same group and storage declaration")
            operations = pin_operation_parents(disposition_operations(boundary, parent, runs, mode), boundary)
            state = parent["path"].parent
        if operations:
            check_state(boundary, state)
            header = {"mode": mode, "group": group, "context": run_context(manifest, group, state),
                      "manifest": digest(manifest), "operations": operations,
                      "parent": parent["header"]["run"] if parent else None,
                      "routes": [str(member.selected) for member in scope.members]}
            if scope.fixed and mode in ("apply", "retire-equal"):
                header["fixed"] = fixed_witnesses(scope, boundary, generated)
            commit_batch(boundary, domain, state, header, rsync, scope, generated, runs)
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
            action = {key: value for key, value in action.items()
                      if key not in ("entry", "observedTarget", "privateParents")}
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
    checks.add_argument("--removed-account", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    changing = args.mode in ("apply", "recover", "retire", "retire-equal", "rollback")
    if changing and not (args.group and args.offline):
        parser.error("Mutation requires --group and an approved --offline window")
    if args.mode in ("recover", "retire", "rollback") and not args.run:
        parser.error("Select a journal with --run")
    if (args.require_noop or args.activation or args.admission or args.removed_account) and args.mode != "check":
        parser.error("Check flags are only valid with check")
    if args.mode == "plan" and not args.group:
        parser.error("Select a group with --group")
    if args.retire_equal and args.mode != "plan":
        parser.error("--retire-equal requires plan")
    try:
        manifest = json.loads(args.manifest.read_text())
        home, state = manifest_paths(manifest)
        boundary = MoveBoundary()
        if args.removed_account:
            incumbent = generation_path(args.incumbent)
            if incumbent is None:
                raise Unsupported("Installed Home Manager generation for removed account is unavailable")
            candidate = {**manifest, "rules": [], "activationWrites": [], "opaque": []}
            activation_gate(candidate, boundary, None, None, incumbent, False)
            return 0
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
        active = active_generations(home, manifest.get("stateHome"), *manifest.get("legacyStateHomes", []))
        if previous and previous not in active:
            raise Unsupported("The supplied previous generation is absent from the active Home Manager GC roots")
        merge_generation_files(generated, home, active)
        if args.mode == "inventory":
            subset = {**manifest, "rules": groups(manifest)[args.group]} if args.group else manifest
            print(json.dumps(inspect_routes(subset, boundary, generated), indent=2))
            return 0
        declarations = tuple(generation_manifests(home, active))
        if changing:
            actions = mutate(manifest, args.mode, args.group, generated, args.rsync,
                             expect=args.expect, run_id=args.run, previous=declarations)
        elif args.mode == "plan":
            operation = "retire-equal" if args.retire_equal else "apply"
            domain = JournalDomain.discover(boundary, manifest, *declarations)
            runs = domain.runs(boundary)
            if unfinished := [run for run in runs if not run["finished"]]:
                raise Conflict(f"Recover outstanding run: {unfinished[0]['path']}")
            if not args.retire_equal and verified_retained_copy(manifest, args.group, runs, boundary, generated):
                actions, operations = [], []
            else:
                actions, operations = plan_group(manifest, args.group, boundary, generated,
                                                 retire_equal=args.retire_equal, state=domain.primary)
            print(json.dumps({"group": args.group, "context": run_context(manifest, args.group, domain.primary),
                              "operation": operation,
                              "actions": list(display_actions(actions)),
                              "transfers": [{"kind": op["kind"], "source": op["source"], "target": op["target"],
                                             "mounts": [op["left"], op["right"]], "sibling": op.get("sibling")}
                                            for op in operations],
                              "expect": authority(manifest, args.group, operations, operation,
                                                  state=domain.primary) if operations else None},
                             indent=2))
            return 0
        else:
            domain = JournalDomain.discover(boundary, manifest, *declarations)
            runs = domain.runs(boundary)
            unfinished = [run for run in runs if not run["finished"]]
            if unfinished:
                raise Conflict(f"Recover outstanding run: {unfinished[0]['path']}")
            selected_groups = [args.group] if args.group else groups(manifest)
            subset = {**manifest, "rules": [
                rule for group in selected_groups
                if not verified_retained_copy(manifest, group, runs, boundary, generated)
                for rule in groups(manifest)[group]
            ]}
            actions = plan(subset, boundary, compare_collisions=True, generated=generated, state=domain.primary)
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
