"""Linux directory resolution for the Home migration's trusted namespace."""

from contextlib import contextmanager
import os
from pathlib import Path
import re
import stat


class Conflict(RuntimeError):
    pass


class Unsupported(Conflict):
    pass


DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
LOCAL_FILESYSTEMS = {"ext4", "xfs", "btrfs", "tmpfs"}


def mountinfo(path):
    def decode(value):
        return Path(re.sub(r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), value))

    for line in path.read_text().splitlines():
        fields = line.split()
        yield fields[0], fields[2], decode(fields[3]), decode(fields[4]), fields[fields.index("-") + 1]


def absolute(value):
    path = Path(value)
    if path.anchor != "/" or ".." in path.parts or "\0" in value:
        raise Unsupported(f"Expected an absolute path without traversal: {path}")
    return path


def identity(info):
    return (info.st_dev, info.st_ino, stat.S_IFMT(info.st_mode))


class MoveBoundary:
    def __init__(self):
        self.uid = os.geteuid()
        self.mounts = {number: (path, fs) for number, _, _, path, fs
                       in mountinfo(Path("/proc/self/mountinfo"))}

    @contextmanager
    def directory(self, path, *, nearest=False, create=False):
        """Walk from / without symlinks. Optionally stop before a missing component."""
        fd = os.open("/", DIRECTORY)
        current = Path("/")
        try:
            for component in path.parts[1:]:
                # A sticky ancestor such as /tmp is safe for existing children
                # owned by the actor or root. Never create directly inside it.
                shared = self.trust(fd, current, sticky_ancestor=True)
                next_path = current / component
                try:
                    child = os.open(component, DIRECTORY, dir_fd=fd)
                except FileNotFoundError:
                    if nearest:
                        break
                    if not create:
                        raise
                    if shared:
                        raise Unsupported(f"Cannot create migration directories in a shared parent: {current}")
                    os.mkdir(component, mode=0o700, dir_fd=fd)
                    child = os.open(component, DIRECTORY, dir_fd=fd)
                    try:
                        os.fsync(child)
                        os.fsync(fd)
                    except BaseException:
                        os.close(child)
                        raise
                except NotADirectoryError as error:
                    raise Unsupported(f"Migration parent is not a directory or is a symlink: {next_path}") from error
                os.close(fd)
                fd, current = child, next_path
            self.trust(fd, current)
            yield fd
        finally:
            os.close(fd)

    def trust(self, fd, path, *, sticky_ancestor=False):
        info = os.fstat(fd)
        shared = bool(info.st_mode & 0o022)
        if info.st_uid not in (0, self.uid) or (shared and not (sticky_ancestor and info.st_mode & stat.S_ISVTX)):
            raise Unsupported(f"Migration directory permits untrusted entry changes: {path}")
        return shared

    def mount(self, fd, path):
        number = next((line.split()[1] for line in Path(f"/proc/self/fdinfo/{fd}").read_text().splitlines()
                       if line.startswith("mnt_id:")), None)
        if number not in self.mounts:
            raise Unsupported(f"Cannot identify migration filesystem: {path}")
        fs = self.mounts[number][1]
        if fs not in LOCAL_FILESYSTEMS:
            raise Unsupported(f"Unsupported migration filesystem {fs}: {path}")
        return number

    def reject_mounts(self, path):
        if any(mount.is_relative_to(path) for mount, _ in self.mounts.values()):
            raise Unsupported(f"Migration entry is or contains a mount point: {path}")

    def writable(self, fd, path):
        if not os.access(".", os.W_OK | os.X_OK, dir_fd=fd, effective_ids=True):
            raise Unsupported(f"Migration parent requires write and search permission: {path}")

    def matches(self, source_fd, source, target_fd, target, entry_device):
        source_mount = self.mount(source_fd, source)
        target_mount = self.mount(target_fd, target)
        return (source_mount == target_mount
                and os.fstat(source_fd).st_dev == entry_device == os.fstat(target_fd).st_dev)

    def same_mount(self, source, target, entry_device):
        with self.directory(source) as source_fd, self.directory(target, nearest=True) as target_fd:
            if not self.matches(source_fd, source, target_fd, target, entry_device):
                raise Unsupported(f"Cross-filesystem or cross-mount rename requires manual migration: {source} -> {target}")
            self.writable(source_fd, source)
            self.writable(target_fd, target)
