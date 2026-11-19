"""Private Linux no-replace moves under caller-authorized parent descriptors."""

import ctypes
from dataclasses import dataclass, field
import errno
import fcntl
import os
import stat


class Denied(ValueError):
    pass


class Conflict(OSError):
    pass


class Unsupported(OSError):
    pass


class OutcomeUnknown(OSError):
    pass


def _directory_identity(fd):
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        raise Denied("parent descriptor must name a directory")
    if fcntl.fcntl(fd, fcntl.F_GETFL) & os.O_PATH:
        raise Unsupported(errno.EBADF, "O_PATH parent cannot be flushed")
    return info.st_dev, info.st_ino


@dataclass(frozen=True, slots=True)
class Leaf:
    """A leaf under a directory the caller has already opened and authorized."""

    parent_fd: int
    name: str
    _parent_identity: tuple[int, int] = field(init=False, repr=False)

    def __post_init__(self):
        if type(self.parent_fd) is not int or self.parent_fd < 0:
            raise Denied("parent must be an open directory descriptor")
        if (type(self.name) is not str or self.name in ("", ".", "..")
                or "/" in self.name or "\0" in self.name):
            raise Denied("entry must be a single relative leaf")
        object.__setattr__(self, "_parent_identity", _directory_identity(self.parent_fd))


@dataclass(frozen=True, slots=True)
class MoveNew:
    """Fixed source, destination, allowed source type and effective UID."""

    actor_uid: int
    source: Leaf
    target: Leaf
    source_type: int

    def __post_init__(self):
        if type(self.actor_uid) is not int or self.actor_uid < 0:
            raise Denied("actor must be an effective UID")
        if type(self.source) is not Leaf or type(self.target) is not Leaf:
            raise Denied("move requires two authorized leaves")
        if type(self.source_type) is not int or self.source_type not in (stat.S_IFREG, stat.S_IFDIR):
            raise Denied("move requires a regular file or directory source")
        if (self.source._parent_identity == self.target._parent_identity
                and self.source.name == self.target.name):
            raise Denied("source and target must be different entries")


def _rename_noreplace(source, target):
    # Linux renameat2 with RENAME_NOREPLACE. The kernel resolves both leaves
    # under the passed descriptors and refuses a mounted-filesystem crossing.
    try:
        renameat2 = ctypes.CDLL(None, use_errno=True).renameat2
    except AttributeError as error:
        raise Unsupported(errno.ENOSYS, "libc has no renameat2") from error
    renameat2.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                          ctypes.c_char_p, ctypes.c_uint)
    renameat2.restype = ctypes.c_int
    if renameat2(source.parent_fd, os.fsencode(source.name),
                target.parent_fd, os.fsencode(target.name), 1) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))


def execute_move(intent, *, confirmed=False):
    """Rename without clobbering, then flush both parents.

    The caller holds the descriptors open and controls substitution of the
    source leaf. The caller also owns approval, journal and any payload flush.
    """
    if type(intent) is not MoveNew or confirmed is not True:
        raise Denied("execution requires a confirmed MoveNew intent")
    if os.geteuid() != intent.actor_uid:
        raise Denied("effective UID differs from the approved actor")
    source, target = intent.source, intent.target
    for leaf in (source, target):
        if _directory_identity(leaf.parent_fd) != leaf._parent_identity:
            raise Denied("parent descriptor differs from the approved directory")
    info = os.stat(source.name, dir_fd=source.parent_fd, follow_symlinks=False)
    if stat.S_IFMT(info.st_mode) != intent.source_type:
        raise Denied("source type differs from the approved type")

    try:
        _rename_noreplace(source, target)
    except Unsupported:
        raise
    except OSError as error:
        if error.errno in (errno.EEXIST, errno.ENOTEMPTY):
            raise Conflict(error.errno, error.strerror) from error
        # EINVAL can also reject a directory move into its own subtree.
        if error.errno in (errno.EXDEV, errno.ENOSYS, errno.EOPNOTSUPP, errno.EINVAL):
            raise Unsupported(error.errno, error.strerror) from error
        if error.errno in (errno.EINTR, errno.EIO, errno.ESTALE, errno.ETIMEDOUT):
            raise OutcomeUnknown(error.errno, "rename outcome unknown") from error
        raise
    except KeyboardInterrupt as error:
        raise OutcomeUnknown("rename interrupted") from error

    try:
        os.fsync(target.parent_fd)
        if source._parent_identity != target._parent_identity:
            os.fsync(source.parent_fd)
    except OSError as error:
        raise OutcomeUnknown(error.errno, "rename returned success but parent flush failed") from error
    except KeyboardInterrupt as error:
        raise OutcomeUnknown("rename returned success but parent flush was interrupted") from error
