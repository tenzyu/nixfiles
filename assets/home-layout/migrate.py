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


def tree(path):
    # Path.rglob may silently suppress permission errors. An unreadable directory
    # must never be classified as empty/generated and moved out of the way.
    with os.scandir(path) as entries:
        for entry in entries:
            child = Path(entry.path)
            yield child
            if entry.is_dir(follow_symlinks=False):
                yield from tree(child)


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


def busy(patterns):
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
                matches.append(proc.name)
        except (OSError, UnicodeError):
            continue
    return matches


def replace_references(text, source, target, home):
    for old in (str(source), "~/" + str(source.relative_to(home)),
                "$HOME/" + str(source.relative_to(home))):
        text = re.sub(re.escape(old) + r"(?=[/\s\"']|$)", lambda _: str(target), text)
    return text


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
                for link in tree(actual_source):
                    if not link.is_symlink():
                        continue
                    value = os.readlink(link)
                    if value.startswith(str(source) + "/") or value == str(source):
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
                if not generated_tree(actual_target) or not actual_source.is_dir():
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
            actions.append({"action": "move", "source": str(source), "target": str(target)})
            moves.append((source, target))
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
    pids = busy(patterns) if patterns else []
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
                if not generated_tree(target) or not source.is_dir():
                    raise Conflict(f"Destination changed during migration: {target}")
                move(target, run / "scaffolding" / str(index))
            move(source, target)
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
