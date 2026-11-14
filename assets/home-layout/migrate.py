"""Home Manager's Linux XDG migration. Check is read-only; apply never merges data."""

import argparse
import ctypes
import datetime
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import tomllib


class Conflict(RuntimeError):
    pass


def exists(path):
    return os.path.lexists(path)


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


def generated_tree(path):
    """Only directories and store links, never regular files or external links."""
    if path.is_symlink() or not path.is_dir():
        return False
    return all(store_link(p) if p.is_symlink() else p.is_dir()
               for p in tree(path))


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


def nearest(path):
    while not exists(path):
        path = path.parent
    return path


def check_parents(path, home):
    # Legacy symlink layouts require an explicit decision, not an implicit move
    # of the symlink or of somebody else's tree.
    for parent in [path, *path.parents]:
        if parent == home:
            break
        if parent.is_symlink():
            raise Conflict(f"Legacy path contains a symlink: {parent}")


def mounts(path):
    for line in path.read_text().splitlines():
        fields = line.split()
        decode = lambda value: Path(re.sub(r"\\([0-7]{3})",
                                          lambda match: chr(int(match[1], 8)), value))
        yield fields[2], decode(fields[3]), decode(fields[4])


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
            actions.append({"action": "symlink", "target": str(new_link),
                            "original": original, "replacement": replacement})
    return actions


def plan(manifest):
    home = Path(manifest["home"])
    moves, actions, patterns = [], [], []
    for rule in manifest["rules"]:
        source, target = Path(rule["source"]), Path(rule["target"])
        if not source.is_absolute() or not target.is_absolute():
            raise Conflict("Migration paths must be absolute")
        if not source.is_relative_to(home) or source == home:
            raise Conflict(f"Source must be below HOME: {source}")
        if source == target:
            continue
        if target.is_relative_to(source) or source.is_relative_to(target):
            raise Conflict(f"Overlapping migration: {source} -> {target}")
        actual_source, actual_target = virtual(source, moves), virtual(target, moves)
        if present(actual_source):
            check_parents(actual_source, home)
            if not (actual_source.is_dir() or actual_source.is_file()):
                raise Conflict(f"Unsupported legacy file type: {source}")
            if actual_source.is_dir():
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
            if present(actual_target):
                generated = generated_tree(actual_target)
                if not generated:
                    if (rule.get("onConflict", "reject") != "backup"
                            or not actual_source.is_dir() or not actual_target.is_dir()
                            or actual_target.is_symlink()):
                        raise Conflict(f"Both paths contain data: {source} -> {target}")
                    # A backup is a rename into the private migration journal.
                    # Refuse if that would become a cross-filesystem move.
                    state_parent = nearest(Path(manifest["state"]))
                    if actual_target.stat().st_dev != state_parent.stat().st_dev:
                        raise Conflict(f"Backup requires same filesystem: {target}")
                elif not actual_source.is_dir():
                    raise Conflict(f"Both paths contain data: {source} -> {target}")
            # HM checks the current layout before writeBoundary. Check files that
            # will appear there after moving, so linkGeneration cannot clobber them.
            for name in manifest.get("managed", []):
                managed = Path(name)
                if managed.is_relative_to(target):
                    old = actual_source / managed.relative_to(target)
                    if exists(old) and not store_link(old):
                        raise Conflict(f"Legacy file would collide with a managed file: {old}")
            future_parent = virtual(target.parent, moves)
            parent = nearest(future_parent if future_parent is not None else target.parent)
            if not parent.is_dir():
                raise Conflict(f"Destination parent is not a directory: {target.parent}")
            if actual_source.stat().st_dev != parent.stat().st_dev:
                raise Conflict(f"Cross-filesystem move requires manual migration: {source} -> {target}")
            actions.append({"action": "move", "source": str(source), "target": str(target),
                            "onConflict": rule.get("onConflict", "reject")})
            moves.append((source, target))
            patterns.extend(rule.get("processes", []))
            if rule.get("repairAbsoluteLinks", False) and actual_source.is_dir():
                actions.extend(link_repairs(actual_source, target, manifest,
                                            [old for old, _ in moves[:-1]]))
        elif (rule.get("repairAbsoluteLinks", False) and present(actual_target)
              and actual_target.is_dir() and not actual_target.is_symlink()):
            # Recover a crash between the directory rename and symlink repair.
            repairs = link_repairs(actual_target, target, manifest)
            actions.extend(repairs)
            if repairs:
                patterns.extend(rule.get("processes", []))

        # Run even when the directory has already moved: a crash between rename
        # and reference repair is recoverable on the next activation.
        for relative in rule.get("references", []):
            dest = target / relative
            actual = virtual(dest, moves)
            if not present(actual) or not actual.is_file():
                continue
            text = actual.read_text()
            updated = replace_references(text, source, target, home)
            if updated == text:
                continue
            if actual.is_symlink():
                raise Conflict(f"Fix old-root references in the declarative source: {actual}")
            if dest.suffix == ".json":
                json.loads(updated)
            elif dest.suffix == ".toml":
                tomllib.loads(updated)
            actions.append({"action": "rewrite", "target": str(dest), "source": str(source),
                            "root": str(target)})
            patterns.extend(rule.get("processes", []))
    paths = [Path(rule[key]) for rule in manifest["rules"] for key in ("source", "target")]
    pids = busy(patterns, paths) if patterns else []
    if pids:
        raise Conflict(f"Close applications before migration (PIDs: {', '.join(pids)})")
    return actions


def rename_noreplace(source, target):
    """Atomic Linux rename, including refusal to replace empty directories."""
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renameat2(-100, os.fsencode(source), -100, os.fsencode(target), 1):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(target))


def apply(manifest):
    actions = plan(manifest)  # Entire batch checked before the first write.
    if not actions:
        return []
    os.umask(0o077)
    state = Path(manifest["state"])
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    run = Path(tempfile.mkdtemp(prefix=datetime.datetime.now().strftime("%Y%m%dT%H%M%S-"), dir=state))

    def journal(event):
        with (run / "operations.jsonl").open("a") as log:
            log.write(json.dumps(event, ensure_ascii=False) + "\n")
            log.flush()
            os.fsync(log.fileno())

    def move(source, target):
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        journal({"action": "move-intent", "source": str(source), "target": str(target)})
        rename_noreplace(source, target)
        # Persist directory entries before recording success.
        for parent in {source.parent, target.parent}:
            fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        journal({"action": "move", "source": str(source), "target": str(target)})

    for index, action in enumerate(actions):
        target = Path(action["target"])
        if action["action"] == "move":
            source = Path(action["source"])
            # Recheck after preflight; never treat a newly created real file as
            # scaffolding, and never use a copying fallback across filesystems.
            if exists(target):
                if not source.is_dir() or target.is_symlink() or not target.is_dir():
                    raise Conflict(f"Destination changed during migration: {target}")
                if generated_tree(target):
                    archive = run / "scaffolding" / str(index)
                elif action["onConflict"] == "backup":
                    archive = run / "conflicts" / str(index)
                else:
                    raise Conflict(f"Destination changed during migration: {target}")
                if target.stat().st_dev != nearest(archive.parent).stat().st_dev:
                    raise Conflict(f"Backup requires same filesystem: {target}")
                move(target, archive)
            move(source, target)
        elif action["action"] == "symlink":
            if not target.is_symlink():
                raise Conflict(f"Symlink changed during migration: {target}")
            current = os.readlink(target)
            replacement = action["replacement"]
            if current == replacement:
                continue
            if current != action["original"]:
                raise Conflict(f"Symlink changed during migration: {target}")
            journal({"action": "symlink-intent", "target": str(target),
                     "original": current, "replacement": replacement})
            fd, temp = tempfile.mkstemp(prefix=".home-migration-link-", dir=target.parent)
            os.close(fd)
            os.unlink(temp)
            try:
                os.symlink(replacement, temp)
                # Only the original symlink may be replaced, never a real file.
                if not target.is_symlink() or os.readlink(target) != current:
                    raise Conflict(f"Symlink changed during migration: {target}")
                os.replace(temp, target)
                fd = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(fd)
                finally:
                    os.close(fd)
            finally:
                if exists(temp):
                    os.unlink(temp)
            journal({"action": "symlink", "target": str(target),
                     "original": current, "replacement": replacement})
        else:
            text = target.read_text()
            updated = replace_references(text, Path(action["source"]), Path(action["root"]),
                                         Path(manifest["home"]))
            if text == updated:
                continue
            if target.is_symlink():
                raise Conflict(f"Reference file became a symlink: {target}")
            backup = run / "references" / str(index)
            backup.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            shutil.copy2(target, backup)
            journal({"action": "rewrite-intent", "target": str(target), "backup": str(backup)})
            fd, temp = tempfile.mkstemp(prefix=".home-migration-", dir=target.parent)
            try:
                with os.fdopen(fd, "w") as output:
                    output.write(updated)
                    output.flush()
                    os.fchmod(output.fileno(), stat.S_IMODE(target.stat().st_mode))
                    os.fsync(output.fileno())
                os.replace(temp, target)
            finally:
                if exists(temp):
                    os.unlink(temp)
            journal({"action": "rewrite", "target": str(target), "backup": str(backup)})
    print(f"Migration journal: {run}")
    return actions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("mode", choices=["check", "apply"], nargs="?", default="check")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    try:
        actions = apply(manifest) if args.mode == "apply" else plan(manifest)
    except (Conflict, OSError, ValueError) as error:
        print(f"home migration stopped: {error}", file=sys.stderr)
        return 1
    print(json.dumps(actions, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
