"""Seed missing Parsec files or review the declared settings in place."""

from contextlib import contextmanager, ExitStack
import errno
import json
import os
import stat
import subprocess
import sys


DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
UNSUPPORTED = (errno.ENOSYS, errno.EOPNOTSUPP, errno.EXDEV)
LEGACY_CONFIG = "config.txt"


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


def mapping_match(stream, expected, mapping_id):
    # Own only one row. Accept it in any position without reordering other rows.
    count = 0
    exact = False
    for raw in stream:
        row = raw.removesuffix(b"\n").removesuffix(b"\r")
        if row.split(None, 1)[:1] == [mapping_id]:
            count += 1
            exact = row + b"\n" == expected
    return count, exact


def inspect_file(parent, path, leaf, read):
    try:
        handle = os.open(leaf, os.O_PATH | os.O_NOFOLLOW, dir_fd=parent)
    except FileNotFoundError:
        current(parent, path)
        return None
    try:
        return observe(parent, path, leaf, handle, read)
    finally:
        os.close(handle)


def observe(parent, path, leaf, handle, read):
    before = os.fstat(handle)
    if not stat.S_ISREG(before.st_mode) or before.st_uid != os.geteuid():
        raise Refusal("Conflict", "existing entry is not a user-owned regular file")
    # O_PATH inspected the type without opening a FIFO/device or following a leaf
    # symlink. Reopen that inode for reading; O_NOATIME leaves a match untouched.
    with os.fdopen(os.open(f"/proc/self/fd/{handle}", os.O_RDONLY | os.O_NOATIME), "rb") as stream:
        observed = read(stream)
        after = os.fstat(stream.fileno())
    try:
        visible = os.stat(leaf, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        raise Refusal("Conflict", "entry disappeared while being inspected") from None
    if identity(visible) != identity(before) or not before.st_ctime_ns == after.st_ctime_ns == visible.st_ctime_ns:
        raise Refusal("Conflict", "entry changed while being inspected")
    current(parent, path)
    return observed, stat.S_IMODE(after.st_mode)


def flush(native, fd):
    # Reuse #50's native fsync operation on the inherited descriptor.
    subprocess.run([sys.executable, "-I", native, "fsync", str(fd)], pass_fds=(fd,), check=True)


def guard_legacy_config(parent, operation):
    if operation == "config":
        try:
            os.stat(LEGACY_CONFIG, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            return
        raise Refusal("AppOwned", f"{LEGACY_CONFIG} exists; skipped the native config seed")


def publish(native, home, parent, path, operation, leaf, expected, mode):
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
            guard_legacy_config(parent, operation)
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


@contextmanager
def directories(directory, *, create):
    home_path = os.environ.get("HOME", "")
    if not home_path.startswith("/") or home_path == "/":
        raise Refusal("Unsupported", "HOME must be an absolute user directory")
    path = f"{home_path}/{directory}"
    with ExitStack() as opened:
        home = open_directory(home_path)
        opened.callback(os.close, home)
        check_directory(home, home_path)
        try:
            parent = open_directory(directory, home)
        except FileNotFoundError:
            if not create:
                yield home, None, path
                return
            try:
                os.mkdir(directory, 0o700, dir_fd=home)
            except FileExistsError:
                pass  # Check the entry installed by the winner, never replace it.
            parent = open_directory(directory, home)
        opened.callback(os.close, parent)
        check_directory(parent, path)
        yield home, parent, path


def activate(native, data, operation, leaf):
    os.umask(0o077)
    mode = int(data["mode"], 8)
    mapping_id = data["mappingId"].encode()
    if operation == "mapping":
        expected = (data["mappingRow"] + "\n").encode()

        def matches(stream):
            return mapping_match(stream, expected, mapping_id) == (1, True)

        difference = "existing mapping does not contain exactly one declared controller row"
    else:
        settings = data["configSettings"]
        document = {key: {"value": value} for key, value in settings.items()}
        expected = (json.dumps(document, indent=2) + "\n").encode()

        def matches(stream):
            observed = json_settings(stream, settings)
            return all(observed.get(key) == [str(value).encode()] for key, value in settings.items())

        difference = "existing config differs from the declaration"

    with directories(data["directory"], create=True) as (home, parent, path):
        observed = inspect_file(parent, path, leaf, matches)
        if observed is None:
            guard_legacy_config(parent, operation)
            publish(native, home, parent, path, operation, leaf, expected, mode)
        else:
            identical, actual_mode = observed
            if actual_mode != mode:
                raise Refusal("Conflict", "existing file mode differs from the declared 0600")
            if not identical:
                raise Refusal("Conflict", difference)


def unique_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("duplicate JSON key")
    return result


def json_settings(stream, keys):
    try:
        document = json.load(stream, object_pairs_hook=unique_object)
        if not isinstance(document, dict):
            raise ValueError("expected JSON object")
    except (ValueError, RecursionError) as error:
        raise Refusal("Conflict", "expected a valid Parsec JSON object with unique keys") from error
    settings = {}
    for key in keys:
        if key in document:
            setting = document[key]
            value = setting.get("value") if isinstance(setting, dict) else None
            settings[key] = [str(value).encode() if type(value) is int else None]
    return settings


def text_settings(stream, keys):
    settings = {}
    for line in stream:
        key, separator, value = line.partition(b"=")
        key = key.strip()
        if separator and key in keys:
            settings.setdefault(key, []).append(value.strip())
    return {key.decode(): values for key, values in settings.items()}


def show_settings(leaf, expected, settings):
    different = False
    for key, value in expected.items():
        observed = settings.get(key, [])
        if not observed:
            state = "missing"
        elif len(observed) > 1:
            state = "multiple assignments"
        elif observed[0] is None:
            state = "unrecognized value format"
        elif observed[0] == str(value).encode():
            state = "present"
        else:
            state = "different value"
        print(f"{leaf}: {key}={value} [{state}]")
        different |= state != "present"
    return int(different)


def review_file(parent, path, leaf, read):
    try:
        return inspect_file(parent, path, leaf, read), 0
    except Refusal as error:
        print(f"{leaf}: {error.result}: {error}.", file=sys.stderr)
        return None, 1
    except OSError as error:
        print(f"{leaf}: IOError: errno {error.errno}: {error.strerror}.", file=sys.stderr)
        return None, 74


def review_config(parent, path, data, mode):
    leaf = data["configFile"]
    expected = data["configSettings"]
    keys = {key.encode() for key in expected}
    modern, json_status = review_file(parent, path, leaf, lambda stream: json_settings(stream, expected))
    legacy, text_status = review_file(parent, path, LEGACY_CONFIG, lambda stream: text_settings(stream, keys))
    status = max(json_status, text_status)
    if modern is not None:
        settings, actual_mode = modern
        status = max(status, show_settings(leaf, expected, settings), show_mode(leaf, actual_mode, mode))
    elif json_status == 0:
        print(f"{leaf}: missing")

    if legacy is None:
        if text_status == 0:
            print(f"{LEGACY_CONFIG}: missing")
        return status if modern is not None else max(status, 1)

    settings, actual_mode = legacy
    status = max(status, show_mode(LEGACY_CONFIG, actual_mode, mode))
    if modern is not None or json_status:
        if settings:
            print(f"{LEGACY_CONFIG}: declared legacy assignments are present alongside {leaf}; review possible import.")
            show_settings(LEGACY_CONFIG, {key: expected[key] for key in settings}, settings)
            return max(status, 1)
        print(f"{LEGACY_CONFIG}: no declared legacy assignments")
        return status
    print(f"{LEGACY_CONFIG}: existing legacy input suppresses the {leaf} seed.")
    return max(status, show_settings(LEGACY_CONFIG, expected, settings))


def show_mode(leaf, actual, expected):
    if actual == expected:
        return 0
    print(f"{leaf}: mode {actual:04o}, expected {expected:04o}")
    return 1


def review_mapping(parent, path, data, mode):
    leaf = data["mappingFile"]
    mapping_id = data["mappingId"]
    row = data["mappingRow"]
    observed, status = review_file(
        parent, path, leaf, lambda stream: mapping_match(stream, (row + "\n").encode(), mapping_id.encode())
    )
    if observed is None:
        if status == 0:
            print(f"{leaf}: missing; declared row: {row}")
        return max(status, 1)
    (count, exact), actual_mode = observed
    status = show_mode(leaf, actual_mode, mode)
    if count == 1 and exact:
        print(f"{leaf}: declared controller row for {mapping_id} present exactly once")
        return status
    print(f"{leaf}: {count} row(s) for {mapping_id}; expected one exact row: {row}")
    return 1


def review(data):
    with directories(data["directory"], create=False) as (_, parent, path):
        if parent is None:
            print(f"$HOME/{data['directory']}: missing; no Parsec files to review")
            return 1
        mode = int(data["mode"], 8)
        return max(review_config(parent, path, data, mode), review_mapping(parent, path, data, mode))


def main():
    if len(sys.argv) != 4 or sys.argv[3] not in ("config", "mapping", "review"):
        print("Usage: parsec-activation-review", file=sys.stderr)
        return 64
    native, policy, operation = sys.argv[1:]
    with open(policy, encoding="utf-8") as stream:
        data = json.load(stream)
    if operation == "review":
        label = f"parsec-activation-review: $HOME/{data['directory']}"
    else:
        leaf = data[operation + "File"]
        label = f"parsec-activation: $HOME/{data['directory']}/{leaf}"
    try:
        if operation == "review":
            return review(data)
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
        if operation == "review":
            return 1
        if error.result == "AppOwned":
            print("  Run parsec-activation-review to compare the declared settings with the saved files.", file=sys.stderr)
            return 0
        if error.result in ("Conflict", "Unsupported"):
            print(
                "  Run parsec-activation-review. Review the settings in Parsec, "
                "or reconcile the file separately with an independent backup and control of all writers.",
                file=sys.stderr,
            )
            return 0  # Compatibility gate: preserve existing data without blocking HM.
        if error.result == "OutcomeUnknown":
            print("  Inspect the final entry before retrying; do not delete it to rerun activation.", file=sys.stderr)
            return 75
        return 74
    except OSError as error:
        detail = "" if operation == "review" else "; no file published by this attempt"
        print(f"{label}: IOError: errno {error.errno}: {error.strerror}{detail}.", file=sys.stderr)
        return 74
    except subprocess.CalledProcessError as error:
        print(f"{label}: could not flush the staged file (status {error.returncode}); no file published.", file=sys.stderr)
        return error.returncode if error.returncode > 0 else 128 - error.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
