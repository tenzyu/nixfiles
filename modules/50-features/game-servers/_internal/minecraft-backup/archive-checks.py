"""Fixed-actor preflight and member validation for the Minecraft writer."""

import os
import stat
import sys
import tarfile
from pathlib import Path, PurePosixPath


def directory(path: Path, boundary: Path) -> None:
    if not path.is_relative_to(boundary) or path.resolve(strict=True) != path:
        raise ValueError(f"unsafe directory path: {path}")
    for component in (path, *path.parents):
        info = component.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid not in (0, os.geteuid()) or info.st_mode & 0o022:
            raise ValueError(f"directory must be owned by root or the archive user and protected from other writers: {component}")
        if component == boundary:
            break


def prepare(boundary: Path, source: Path, destination: Path) -> None:
    world = source / "world"
    directory(world, boundary)
    directory(destination, boundary)
    info = destination.stat()
    if info.st_uid != os.geteuid() or info.st_gid != os.getegid():
        raise ValueError(f"backup directory has the wrong owner: {destination}")
    level = world / "level.dat"
    info = level.lstat()
    if not stat.S_ISREG(info.st_mode) or not info.st_size:
        raise ValueError(f"expected nonempty regular world data: {level}")
    with level.open("rb") as stream:
        stream.read(1)
    if not os.access(source, os.R_OK | os.X_OK) or not os.access(world, os.R_OK | os.X_OK):
        raise PermissionError(f"archive user cannot read and enter {source} and {world}")
    if not os.access(destination, os.R_OK | os.W_OK | os.X_OK):
        raise PermissionError(f"archive user cannot read and write {destination}")

    # Bootstrap only under the archive UID. O_EXCL never follows or modifies an
    # existing entry. Keep this inode for subsequent writer invocations.
    lock = destination / ".safety.lock"
    try:
        os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_RDONLY | os.O_NOFOLLOW, 0o400))
    except FileExistsError:
        pass
    info = lock.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o022:
        raise ValueError(f"expected a protected archive-user regular lock: {lock}")


def validate(stage: Path) -> None:
    root = world = level = False
    required = {PurePosixPath(name) for name in ("survival", "survival/world", "survival/world/level.dat")}
    seen = set()
    with tarfile.open(stage, "r|gz") as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if not path.parts or path.parts[0] != "survival" or ".." in path.parts:
                raise ValueError(f"archive member outside survival: {member.name!r}")
            if path in required:
                if path in seen:
                    raise ValueError(f"duplicate required archive member: {member.name!r}")
                seen.add(path)
            if path == PurePosixPath("survival"):
                root = member.isdir()
            if path == PurePosixPath("survival/world"):
                world = member.isdir()
            if path == PurePosixPath("survival/world/level.dat"):
                level = member.isreg() and member.size > 0
    if not (root and world and level):
        raise ValueError("archive lacks survival/world/level.dat or its directories")


try:
    operation, *paths = sys.argv[1:]
    if operation == "prepare":
        prepare(*map(Path, paths))
    elif operation == "validate":
        validate(*map(Path, paths))
    else:
        sys.exit(64)
except (ValueError, RuntimeError, OSError, EOFError, tarfile.TarError) as error:
    status = 74 if isinstance(error, OSError) else 69
    print(f"minecraft-archive: {'IOError' if status == 74 else 'Unsupported'}: {error}", file=sys.stderr)
    sys.exit(status)
