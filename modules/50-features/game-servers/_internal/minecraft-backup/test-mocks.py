"""Inert substitutes for container, systemctl, tar failures and sync failures."""

import errno
import fcntl
import os
import stat
import sys
import time
from pathlib import Path

role, root, program, *args = sys.argv[1:]
root = Path(root)


def read(name: str) -> str:
    return (root / "control" / name).read_text().strip()


def event(message: str) -> None:
    with (root / "control/events").open("a") as stream:
        print(message, file=stream)


def block(kind: str) -> None:
    (root / f"control/{kind}-ready").touch()
    for _ in range(800):
        if (root / f"control/{kind}-release").exists():
            return
        time.sleep(0.01)
    sys.exit(124)


def unit(guest: bool, command: str, *flags: str) -> None:
    side = "guest" if guest else "host"
    queue = root / f"control/{side}-job"
    service = "minecraft-server-survival.service" if guest else "container@fixture-mc.service"
    event(f"{side} {command}")
    state = read(side)
    if command == "show":
        assert flags[-1] == service
        if state == "unknown":
            sys.exit(5)
        active = state in ("running", "running-job")
        inactive = state in ("inactive", "unclean", "inactive-tasks")
        props = {
            "LoadState": "not-found" if state == "missing" else "loaded",
            "ActiveState": "active" if active else "inactive" if inactive else "failed" if state == "failed" else "deactivating",
            "SubState": "running" if active else "dead" if inactive else "stop-sigterm",
            "Result": "timeout" if state == "failed" else "success",
            "Job": "48" if queue.exists() or state in ("running-job", "transition") else "0",
            "MainPID": "123" if active else "0",
            "ControlPID": "0",
            "ControlGroup": "/system.slice/minecraft.service" if active or state == "inactive-tasks" else "",
            "TasksCurrent": "2" if active or state == "inactive-tasks" else "[not set]",
            "ExecMainPID": "123",
            "ExecMainCode": "2" if state == "unclean" else "1",
            "ExecMainStatus": "15" if state == "unclean" else "0",
        }
        for key, value in props.items():
            print(f"{key}={value}")
    elif command == "list-jobs":
        assert flags == ("--no-pager", "--full")
        if state == "unknown":
            sys.exit(5)
        if queue.exists():
            print(f"48 {service} {queue.read_text()} running")
        else:
            print("No jobs running.")
    elif command == "stop":
        behavior = read("stop")
        if behavior in ("block", "disconnect"):
            (root / "run/minecraft.lock.job").stat()
            queue.write_text(command)
            if behavior == "disconnect":
                sys.exit(31)
            block("stop")
            behavior = "inactive"
            queue.unlink()
        (root / f"control/{side}").write_text(behavior)
        if behavior == "unknown":
            sys.exit(31)
    elif command in ("start", "restart"):
        behavior = read("resume" if guest else "host-start")
        if behavior == "disconnect":
            (root / "run/minecraft.lock.job").stat()
            queue.write_text(command)
            sys.exit(32 if guest else 33)
        if behavior == "return-failure":
            sys.exit(32)
        (root / f"control/{side}").write_text(behavior)
    else:
        sys.exit(64)


if role == "container":
    assert args[:3] == ["run", "fixture-mc", "--"]
    if args[3].endswith("/systemctl"):
        assert args[4] == "--no-ask-password"
        unit(True, *args[5:])
    else:
        # Administrative payloads cannot inherit this lock descriptor.
        if args[3] != "tmux":
            assert all(os.readlink(entry) != str(root / "run/minecraft.lock")
                       for entry in Path("/proc/self/fd").iterdir() if entry.is_symlink())
        event(f"guest payload {args[3]}")
        if read("admin") == "block":
            block("admin")
elif role == "host":
    assert args.pop(0) == "--no-ask-password"
    unit(False, *args)
elif role == "setpriv":
    assert args[4:7] == ["--clear-groups", "--no-new-privs", "--"]
    action, archive_fd = args[8], int(args[10])
    event(f"writer {action}")
    if read("transition") == "drop-fd":
        os.close(archive_fd)
    os.execv(args[7], args[7:])
elif role == "producer":
    mode = read("io")
    event("tar")
    if mode == "block":
        lifecycle = [entry for entry in Path("/proc/self/fd").iterdir() if entry.is_symlink()
                     and os.readlink(entry) == str(root / "run/minecraft.lock")]
        assert len(lifecycle) == 1, lifecycle
        # An independent open description would conflict with the coordinator.
        # This succeeds only on the inherited description while it holds flock.
        fcntl.flock(int(lifecycle[0].name), fcntl.LOCK_EX | fcntl.LOCK_NB)
        block("tar")
    if mode == "enospc":
        os.write(1, b"partial archive")
        print(os.strerror(errno.ENOSPC), file=sys.stderr)
        sys.exit(28)
    if mode == "bad-gzip":
        os.write(1, b"invalid gzip")
    elif mode == "bad-tar":
        import gzip
        os.write(1, gzip.compress(b"invalid tar" * 100))
    elif mode == "missing-world":
        os.execv(program, [program, "-czf", "-", "-C", str(root / "data"), "--exclude=level.dat", "survival"])
    else:
        os.execv(program, [program, *args])
elif role == "native":
    action, fd = args[:2]
    point = action
    if action == "fsync":
        point = "directory-sync" if stat.S_ISDIR(os.fstat(int(fd)).st_mode) else "file-sync"
    event(point)
    if read("io") == point:
        print(f"IOError: {action}: errno {errno.EIO}: {os.strerror(errno.EIO)}", file=sys.stderr)
        sys.exit(74)
    os.execv(sys.executable, [sys.executable, "-I", program, *args])
else:
    sys.exit(64)
