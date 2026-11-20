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
        self.mounts = self.mount_table()

    @staticmethod
    def mount_table():
        return {number: (device, root, path, fs) for number, device, root, path, fs
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

    def mount(self, fd, path, *, refresh=True):
        number = next((line.split()[1] for line in Path(f"/proc/self/fdinfo/{fd}").read_text().splitlines()
                       if line.startswith("mnt_id:")), None)
        if number not in self.mounts or (refresh and self.mount_table().get(number) != self.mounts[number]):
            raise Unsupported(f"Cannot identify migration filesystem: {path}")
        device, root, mountpoint, fs = self.mounts[number]
        if fs not in LOCAL_FILESYSTEMS:
            raise Unsupported(f"Unsupported migration filesystem {fs}: {path}")
        if root != Path("/") or any(
                key != number and entry[:2] == (device, root) for key, entry in self.mounts.items()):
            raise Unsupported(f"Bind or non-root filesystem view requires manual review: {mountpoint}")
        return number

    def reject_mounts(self, path):
        if any(mount.is_relative_to(path) for _, _, mount, _ in self.mount_table().values()):
            raise Unsupported(f"Migration entry is or contains a mount point: {path}")

    def entry(self, path):
        """Resolve a leaf without following any symlink; distinguish missing parents."""
        try:
            with self.directory(path.parent) as fd:
                return os.stat(path.name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            return None

    def mount_at(self, path):
        with self.directory(path, nearest=True) as fd:
            return self.mount(fd, path)

    def anchor(self, path):
        with self.directory(path, nearest=True) as fd:
            resolved = os.readlink(f"/proc/self/fd/{fd}")
            return [resolved, list(identity(os.fstat(fd))), self.mount(fd, path)]

    def check_capacity(self, path, bytes_needed):
        with self.directory(path, nearest=True) as fd:
            fs = os.fstatvfs(fd)
            if fs.f_bavail * fs.f_frsize < bytes_needed or fs.f_favail == 0:
                raise Unsupported(f"Insufficient staging capacity: {path}")

    def writable(self, fd, path):
        if not os.access(".", os.W_OK | os.X_OK, dir_fd=fd, effective_ids=True):
            raise Unsupported(f"Migration parent requires write and search permission: {path}")

    def matches(self, source_fd, source, target_fd, target, entry_device):
        source_mount = self.mount(source_fd, source)
        target_mount = self.mount(target_fd, target)
        return (source_mount == target_mount
                and os.fstat(source_fd).st_dev == entry_device == os.fstat(target_fd).st_dev)
