"""Home Manager Parsec adapter: inspect existing leaves or publish a new inode."""

import errno
import json
import os
import stat
import subprocess
import sys


DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
UNSUPPORTED = (errno.ENOSYS, errno.EOPNOTSUPP, errno.EXDEV)


class Refusal(Exception):
    def __init__(self, result, reason):
        self.result = result
        super().__init__(reason)


def identity(info):
    return info.st_dev, info.st_ino


def current(fd, path):
    # An observation, not a reservation. All operations stay on the opened dirfd.
    if os.readlink(f"/proc/self/fd/{fd}") != path:
        raise Refusal("Unsupported", "HOME or Parsec directory is not canonical or moved")


def check_directory(fd, path):
    current(fd, path)
    info = os.fstat(fd)
    if info.st_uid != os.geteuid() or info.st_mode & 0o022:
        raise Refusal("Unsupported", "HOME and Parsec directory must be user-owned and not group/other writable")


def open_directory(path, parent=None):
    try:
        return os.open(path, DIR, dir_fd=parent)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            raise Refusal("Unsupported", "HOME and Parsec directory must be real directories") from error
        raise


def matches(stream, expected, mapping_id):
    if mapping_id is None:
        return stream.read(len(expected) + 1) == expected
    # Own only one row. Accept it in any position without reordering other rows.
    count = 0
    exact = False
    for raw in stream:
        row = raw.removesuffix(b"\n").removesuffix(b"\r")
        if row.split(None, 1)[:1] == [mapping_id]:
            count += 1
            exact = row + b"\n" == expected
    return count == 1 and exact


def observe(parent, leaf, handle, expected, mapping_id, mode):
    before = os.fstat(handle)
    if not stat.S_ISREG(before.st_mode) or before.st_uid != os.geteuid():
        raise Refusal("Conflict", "existing entry is not a user-owned regular file")
    # O_PATH inspected the type without opening a FIFO/device or following a leaf
    # symlink. Reopen that inode for reading; O_NOATIME leaves a match untouched.
    with os.fdopen(os.open(f"/proc/self/fd/{handle}", os.O_RDONLY | os.O_NOATIME), "rb") as stream:
        identical = matches(stream, expected, mapping_id)
        after = os.fstat(stream.fileno())
    try:
        visible = os.stat(leaf, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        raise Refusal("Conflict", "entry disappeared while being inspected") from None
    if identity(visible) != identity(before) or not before.st_ctime_ns == after.st_ctime_ns == visible.st_ctime_ns:
        raise Refusal("Conflict", "entry changed while being inspected")
    if stat.S_IMODE(after.st_mode) != mode:
        raise Refusal("Conflict", "existing file mode differs from the declared 0600")
    if not identical:
        reason = "existing config differs from the declaration" if mapping_id is None else (
            "existing mapping does not contain exactly one declared controller row"
        )
        raise Refusal("Conflict", reason)


def flush(native, fd):
    # Reuse #50's native fsync operation on the inherited descriptor.
    subprocess.run([sys.executable, "-I", native, "fsync", str(fd)], pass_fds=(fd,), check=True)


def publish(native, home, parent, path, leaf, expected, mode):
    try:
        stage = os.open(".", os.O_TMPFILE | os.O_RDWR, mode, dir_fd=parent)
    except OSError as error:
        if error.errno in (*UNSUPPORTED, errno.EINVAL, errno.EISDIR):
            raise Refusal("Unsupported", "filesystem does not support unnamed staging") from error
        raise

    with os.fdopen(stage, "w+b") as staged:
        staged.write(expected)
        staged.seek(0)
        info = os.fstat(stage)
        if staged.read() != expected or stat.S_IMODE(info.st_mode) != mode or info.st_nlink != 0:
            raise Refusal("IOError", "staged content or metadata did not validate")
        flush(native, stage)
        current(parent, path)
        # Follow the kernel's procfd reference to the anonymous inode. Supplying
        # both dirfds makes this linkat. It fails on ANY existing final leaf.
        proc = os.open("/proc/self/fd", DIR)
        try:
            try:
                os.link(str(stage), leaf, src_dir_fd=proc, dst_dir_fd=parent, follow_symlinks=True)
            except FileExistsError:
                raise Refusal("Conflict", "another writer created the final entry before publication") from None
            except OSError as error:
                if error.errno in (*UNSUPPORTED, errno.EPERM):
                    raise Refusal("Unsupported", "filesystem does not support descriptor-based publication") from error
                if error.errno not in (errno.EACCES, errno.EDQUOT, errno.EMLINK, errno.ENOSPC, errno.EROFS):
                    raise Refusal("OutcomeUnknown", "link did not confirm publication") from error
                raise
        finally:
            os.close(proc)

        try:
            flush(native, parent)
            # Also persist the .parsec entry, even if another activation created it.
            flush(native, home)
            current(parent, path)
            if identity(os.stat(leaf, dir_fd=parent, follow_symlinks=False)) != identity(info):
                raise Refusal("OutcomeUnknown", "published inode no longer at final name")
        except (OSError, Refusal, subprocess.CalledProcessError) as error:
            raise Refusal("OutcomeUnknown", "final may be visible; could not confirm publication") from error


def activate(native, data, operation, leaf):
    home_path = os.environ.get("HOME", "")
    if not home_path.startswith("/") or home_path == "/":
        raise Refusal("Unsupported", "HOME must be an absolute user directory")
    home = open_directory(home_path)
    check_directory(home, home_path)
    directory = data["directory"]
    path = f"{home_path}/{directory}"
    os.umask(0o077)
    try:
        parent = open_directory(directory, home)
    except FileNotFoundError:
        try:
            os.mkdir(directory, 0o700, dir_fd=home)
        except FileExistsError:
            pass  # Check the entry installed by the winner, never replace it.
        parent = open_directory(directory, home)
    check_directory(parent, path)

    mode = int(data["mode"], 8)
    mapping_id = data["mappingId"].encode() if operation == "mapping" else None
    expected = (data["mappingRow"] + "\n" if mapping_id else data["configText"]).encode()
    try:
        handle = os.open(leaf, os.O_PATH | os.O_NOFOLLOW, dir_fd=parent)
    except FileNotFoundError:
        publish(native, home, parent, path, leaf, expected, mode)
    else:
        observe(parent, leaf, handle, expected, mapping_id, mode)
        current(parent, path)


def main():
    native, policy, operation = sys.argv[1:]
    with open(policy, encoding="utf-8") as stream:
        data = json.load(stream)
    if operation not in ("config", "mapping"):
        return 64
    leaf = data[operation + "File"]
    label = f"parsec-activation: $HOME/{data['directory']}/{leaf}"
    try:
        activate(native, data, operation, leaf)
    except Refusal as error:
        cause = error.__cause__
        detail = ""
        if isinstance(cause, OSError):
            detail = f" (errno {cause.errno}: {cause.strerror})"
        elif isinstance(cause, subprocess.CalledProcessError):
            detail = f" (fsync status {cause.returncode})"
        elif isinstance(cause, Refusal):
            detail = f" ({cause})"
        print(f"{label}: {error.result}: {error}{detail}.", file=sys.stderr)
        if error.result in ("Conflict", "Unsupported"):
            print(
                "  Activation did not replace existing data. Review the settings in Parsec, "
                "or reconcile the file separately with an independent backup and control of all writers.",
                file=sys.stderr,
            )
            return 0  # Compatibility gate: preserve existing data without blocking HM.
        if error.result == "OutcomeUnknown":
            print("  Inspect the final entry before retrying; do not delete it to rerun activation.", file=sys.stderr)
            return 75
        return 74
    except OSError as error:
        print(f"{label}: IOError: errno {error.errno}: {error.strerror}; no file published by this attempt.", file=sys.stderr)
        return 74
    except subprocess.CalledProcessError as error:
        print(f"{label}: could not flush the staged file (status {error.returncode}); no file published.", file=sys.stderr)
        return error.returncode if error.returncode > 0 else 128 - error.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
