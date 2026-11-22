#!/usr/bin/env python3
"""HOME Authority v1.1 physical-tree mutation experiment, disposable VM only.

No security guarantee is inferred from a syscall returning EPERM alone.
An unprivileged actor executes each operation; the root controller compares
the *actual* object graph before and after. Root only seeds and cleans
isolated test fixtures, never an actual user HOME.
"""
import ctypes
import errno
import hashlib
import json
import mmap
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

HOME = Path("/home/fixture")
FIXTURE = HOME / ".local/share/authority/v11-mutation-fixture"
EXTERNAL = Path("/run/home-authority-v11-control")
DENY = {errno.EACCES, errno.EPERM, errno.EROFS}
ACTIONS = (
    "read_control", "create", "openat_create", "mkdir", "symlink", "hardlink",
    "rename", "rename_exchange", "unlink", "rmdir", "write", "pwrite",
    "append", "truncate", "ftruncate", "mmap_shared", "fallocate",
    "chmod", "utime", "setxattr",
)


def graph(path):
    """Observable protected name, content and metadata; excludes access-time."""
    result = {}
    for root, dirs, files in os.walk(path, followlinks=False):
        for name in sorted(dirs + files):
            obj = Path(root) / name
            entry = str(obj.relative_to(path))
            s = obj.lstat()
            kind = "link" if stat.S_ISLNK(s.st_mode) else "dir" if stat.S_ISDIR(s.st_mode) else "file"
            digest = (
                os.readlink(obj) if kind == "link"
                else hashlib.sha256(obj.read_bytes()).hexdigest() if kind == "file"
                else None
            )
            result[entry] = {
                "kind": kind, "mode": stat.S_IMODE(s.st_mode),
                "size": s.st_size if kind == "file" else None,
                "digest": digest, "mtime_ns": s.st_mtime_ns,
            }
    return result


def seed(path):
    if path.exists() or path.is_symlink():
        shutil.rmtree(path)
    path.mkdir(mode=0o700, parents=True)
    os.chown(path, 1000, 100)
    for name, data in (("target", b"BASELINE\n"), ("other", b"OTHER\n")):
        f = path / name
        f.write_bytes(data)
        os.chown(f, 1000, 100)
        f.chmod(0o600)
    (path / "empty").mkdir()
    os.chown(path / "empty", 1000, 100)
    (path / "empty").chmod(0o700)


def run_child(action, location):
    proc = subprocess.run(
        ["runuser", "-u", "fixture", "--", sys.executable, __file__,
         "child", action, str(location)],
        capture_output=True, text=True, timeout=15,
    )
    try:
        report = json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(
            f"unreadable probe output: {action}: rc={proc.returncode} "
            f"out={proc.stdout[:300]!r} err={proc.stderr[:300]!r}"
        )
    if proc.returncode != 0:
        raise RuntimeError(f"probe crashed: {action}: {report}, {proc.stderr[:300]}")
    return report


def mutate(action, path):
    target, other, new, empty = (
        path / "target", path / "other", path / "new", path / "empty"
    )
    if action == "read_control":
        assert target.read_bytes() == b"BASELINE\n"
    elif action == "create":
        new.write_bytes(b"created")
    elif action == "openat_create":
        d = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            f = os.open("new", os.O_CREAT | os.O_EXCL | os.O_WRONLY,
                        0o600, dir_fd=d)
            os.write(f, b"openat")
            os.close(f)
        finally:
            os.close(d)
    elif action == "mkdir":
        new.mkdir()
    elif action == "symlink":
        new.symlink_to(target)
    elif action == "hardlink":
        os.link(target, new)
    elif action == "rename":
        target.rename(new)
    elif action == "rename_exchange":
        libc = ctypes.CDLL(None, use_errno=True)
        fn = libc.renameat2
        fn.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        fn.restype = ctypes.c_int
        if fn(-100, os.fsencode(target), -100, os.fsencode(other), 2) != 0:
            code = ctypes.get_errno()
            raise OSError(code, os.strerror(code))
    elif action == "unlink":
        target.unlink()
    elif action == "rmdir":
        empty.rmdir()
    elif action == "write":
        target.write_bytes(b"CHANGED!\n")
    elif action == "pwrite":
        f = os.open(target, os.O_WRONLY)
        try:
            os.pwrite(f, b"X", 0)
        finally:
            os.close(f)
    elif action == "append":
        with target.open("ab") as f:
            f.write(b"APPEND")
            f.flush()
            os.fsync(f.fileno())
    elif action == "truncate":
        os.truncate(target, 1)
    elif action == "ftruncate":
        f = os.open(target, os.O_WRONLY)
        try:
            os.ftruncate(f, 2)
        finally:
            os.close(f)
    elif action == "mmap_shared":
        f = os.open(target, os.O_RDWR)
        try:
            with mmap.mmap(f, 0, flags=mmap.MAP_SHARED,
                           prot=mmap.PROT_READ | mmap.PROT_WRITE) as mapped:
                mapped[0:1] = b"M"
                mapped.flush()
        finally:
            os.close(f)
    elif action == "fallocate":
        f = os.open(target, os.O_WRONLY)
        try:
            os.posix_fallocate(f, 0, 4096)
        finally:
            os.close(f)
    elif action == "chmod":
        os.chmod(target, 0o644)
    elif action == "utime":
        os.utime(target, ns=(946684800000000000, 946684800000000000))
    elif action == "setxattr":
        os.setxattr(target, "user.homeauthority", b"changed")
    else:
        raise ValueError(action)


def child(action, location):
    try:
        mutate(action, location)
    except OSError as exc:
        print(json.dumps({
            "result": "denied" if exc.errno in DENY else "unsupported_or_error",
            "errno": exc.errno, "detail": str(exc)[:280],
        }))
    else:
        print(json.dumps({"result": "completed"}))


def private_namespace_legacy_view():
    """Can an ordinary UID build its own compatibility HOME mount view?

    A user namespace is intentionally attempted without host root
    privileges. If unavailable, this is *not* evidence of global denial.
    """
    alias = EXTERNAL / ".legacy"
    alias.mkdir(mode=0o700)
    os.chown(alias, 1000, 100)
    marker = alias / "inside"
    marker.write_text("forbidden private view")
    os.chown(marker, 1000, 100)
    script = 'mount --bind "$1" "$2" && test -f "$2/.legacy/inside"'
    cmd = [
        "runuser", "-u", "fixture", "--",
        "unshare", "--user", "--map-root-user", "--mount",
        "--propagation", "private", "--",
        "sh", "-c", script, "sh", str(EXTERNAL), str(HOME),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    return {
        "untrusted_host_uid": 1000,
        "attempted": True,
        "exit_code": result.returncode,
        "result": "VIOLATION" if result.returncode == 0 else "UNAVAILABLE_OR_DENIED",
        "stderr": result.stderr[-450:],
        "physical_legacy_remains_absent": not os.path.lexists(HOME / ".legacy"),
        "note": ("The root/user-namespace view is not a trusted administrator; "
                 "a failed unshare/mount must not be misreported as enforcement."),
    }


def controller():
    if os.geteuid() != 0:
        raise RuntimeError("root test controller required; actor is separate UID")
    if not HOME.is_dir() or not (HOME / ".local/share/authority/incumbent").is_file():
        raise RuntimeError("sealed fixture not initialized")
    if os.path.lexists(HOME / ".legacy"):
        raise RuntimeError("legacy path exists before v1.1 mutation probe")
    if str(FIXTURE).startswith("/home/fixture/") is False:
        raise RuntimeError("unexpected test location")
    results = {}
    # The external control is required to prove that the probe runner works.
    try:
        seed(EXTERNAL)
        before = graph(EXTERNAL)
        control = run_child("write", EXTERNAL)
        after = graph(EXTERNAL)
        if control["result"] != "completed" or before == after:
            raise RuntimeError("unprotected external negative control did not mutate")
        for action in ACTIONS:
            seed(FIXTURE)
            previous = graph(FIXTURE)
            outcome = run_child(action, FIXTURE)
            current = graph(FIXTURE)
            changed = previous != current
            if outcome["result"] == "completed" and changed:
                verdict = "VIOLATION"
            elif outcome["result"] == "denied" and not changed:
                verdict = "DENIED"
            elif action == "read_control" and outcome["result"] == "completed" and not changed:
                verdict = "READ_OK"
            else:
                verdict = "ERROR_OR_UNSUPPORTED"
            results[action] = {
                "verdict": verdict, "changed_protected_graph": changed,
                "process": outcome,
            }
        counts = {
            label: sum(1 for v in results.values() if v["verdict"] == label)
            for label in ("VIOLATION", "DENIED", "READ_OK", "ERROR_OR_UNSUPPORTED")
        }
        private_legacy = private_namespace_legacy_view()
        if not private_legacy["physical_legacy_remains_absent"]:
            raise RuntimeError("namespace probe escaped into physical HOME")
        return {
            "schema": "home-authority-v11-mutation/v1",
            "physical_home": str(HOME),
            "fixture_under_physical_home": True,
            "unprivileged_actor_uid": 1000,
            "root_fixture_setup_is_explicit_trusted_transition": True,
            "external_negative_control_mutated": True,
            "private_namespace_legacy_view": private_legacy,
            "results": results, "counts": counts,
            "home_immutability_admission": (
                "PASS" if counts["VIOLATION"] == 0
                and counts["ERROR_OR_UNSUPPORTED"] == 0 else "BLOCKED"
            ),
        }
    finally:
        # These are test-only subtrees. No host file is touched.
        if FIXTURE.exists():
            shutil.rmtree(FIXTURE)
        if EXTERNAL.exists():
            shutil.rmtree(EXTERNAL)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "child":
        child(sys.argv[2], Path(sys.argv[3]))
    elif len(sys.argv) == 2 and sys.argv[1] == "probe":
        print(json.dumps(controller(), sort_keys=True))
    else:
        raise SystemExit("usage: v11-mutation-probes.py probe|child ACTION PATH")
