#!/usr/bin/env python3
"""Independent fail-closed HOME authority acceptance test, disposable VM only.

Do not reuse the diagnostic negative-control module or probe. The holder opens
FDs BEFORE HM activation; verify tests the result AFTER activation.
"""
import ctypes
import errno
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time

HOME = Path("/home/fixture")
CANONICAL = HOME / ".local/share/authority"
LEGACY = HOME / ".legacy"
BLOCKED = HOME / ".blocked"
SOCK = Path("/run/home-authority-held-fds/probe.sock")
DENIALS = {errno.EACCES, errno.EPERM, errno.EROFS}


def inspect(label, operation):
    try:
        operation()
    except OSError as exc:
        return {"label": label, "result": "denied" if exc.errno in DENIALS else "error", "errno": exc.errno}
    return {"label": label, "result": "allowed"}


def reset_blocked():
    if BLOCKED.is_symlink() or BLOCKED.is_file():
        BLOCKED.unlink()
    elif BLOCKED.is_dir():
        shutil.rmtree(BLOCKED)


def direct_probes():
    if os.geteuid() != HOME.stat().st_uid:
        raise RuntimeError("probe must run as HOME owner, not privileged root")
    control = CANONICAL / "authorized-control"
    control.write_text("writable canonical\n")
    if control.read_text() != "writable canonical\n":
        raise RuntimeError("canonical write did not persist")
    results = [{"label": "canonical-writer", "result": "allowed"}]
    if os.path.lexists(BLOCKED):
        raise RuntimeError("blocked destination exists: would disguise failure as EEXIST")

    def open_name():
        fd = os.open(BLOCKED, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)

    (CANONICAL / "rename-source").write_text("rename fixture")
    (CANONICAL / "link-source").write_text("link fixture")
    (CANONICAL / "restore-source").write_text("restore fixture")

    fd = os.open(HOME, os.O_RDONLY | os.O_DIRECTORY)
    try:
        def openat_name():
            new = os.open(".blocked", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
            os.close(new)

        def renameat2_name():
            libc = ctypes.CDLL(None, use_errno=True)
            func = getattr(libc, "renameat2", None)
            if func is None:
                raise OSError(errno.ENOSYS, "renameat2 unavailable")
            func.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
            func.restype = ctypes.c_int
            if func(-100, os.fsencode(CANONICAL / "rename-source"), -100, os.fsencode(BLOCKED), 1) != 0:
                e = ctypes.get_errno()
                raise OSError(e, os.strerror(e))

        actions = [
            ("open", open_name),
            ("openat-preopened-home", openat_name),
            ("renameat2", renameat2_name),
            ("linkat", lambda: os.link(CANONICAL / "link-source", ".blocked", dst_dir_fd=fd)),
            ("symlinkat", lambda: os.symlink(str(CANONICAL), ".blocked", dir_fd=fd)),
            ("restore", lambda: shutil.copyfile(CANONICAL / "restore-source", BLOCKED)),
        ]
        for name, action in actions:
            result = inspect(name, action)
            results.append(result)
            if result["result"] == "allowed":
                reset_blocked()
    finally:
        os.close(fd)
    return results


def hold():
    CANONICAL.mkdir(parents=True, exist_ok=True)
    LEGACY.mkdir(exist_ok=True)
    (LEGACY / "incumbent").write_text("before\n")
    homefd = os.open(HOME, os.O_RDONLY | os.O_DIRECTORY)
    legacyfd = os.open(LEGACY, os.O_RDONLY | os.O_DIRECTORY)
    filefd = os.open(LEGACY / "incumbent", os.O_WRONLY | os.O_APPEND)
    SOCK.parent.mkdir(parents=True, exist_ok=True)
    if SOCK.exists():
        SOCK.unlink()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(SOCK))
        server.listen(1)
        # This MUST happen after obtaining the FDs and before HM activation.
        address = os.environ.get("NOTIFY_SOCKET")
        if not address:
            raise RuntimeError("PRESEAL ORDER NOT PROVEN: Type=notify required")
        if address.startswith("@"):
            address = "\0" + address[1:]
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notify:
            notify.sendto(b"READY=1", address)
        conn, _ = server.accept()
        with conn:
            if conn.recv(64).strip() != b"verify":
                raise RuntimeError("unexpected witness command")

            def create_at(fd, basename):
                created = os.open(basename, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
                try:
                    os.write(created, b"old-dir-fd\n")
                finally:
                    os.close(created)

            results = [
                inspect("held-home-dirfd-create", lambda: create_at(homefd, ".blocked")),
                inspect("held-legacy-dirfd-create", lambda: create_at(legacyfd, "ghost")),
                inspect("held-legacy-filefd-append", lambda: os.write(filefd, b"old-file-fd\n")),
            ]
            conn.sendall(json.dumps(results).encode())
    os.close(filefd)
    os.close(legacyfd)
    os.close(homefd)


def user_run(namespace=False):
    cmd = ["runuser", "-u", "fixture", "--", sys.executable, __file__, "unwrapped"]
    if namespace:
        cmd = ["unshare", "--mount", "--propagation", "private", "--", *cmd]
    process = subprocess.run(cmd, text=True, capture_output=True)
    if process.returncode:
        raise RuntimeError(f"independent user probe unavailable: {process.returncode} {process.stderr[:400]}")
    return json.loads(process.stdout)


def verify():
    for _ in range(100):
        if SOCK.is_socket():
            break
        time.sleep(0.1)
    else:
        raise RuntimeError("PRESEAL WITNESS MISSING")

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(str(SOCK))
        sock.sendall(b"verify\n")
        held = json.loads(sock.recv(65536))

    failures = []
    for result in held:
        name, outcome = result["label"], result["result"]
        if outcome == "error":
            failures.append(f"{name}: unexpected errno={result['errno']}")
        elif outcome == "allowed":
            if name == "held-legacy-dirfd-create":
                ghost = CANONICAL / "ghost"
                if not ghost.is_file() or ghost.read_bytes() != b"old-dir-fd\n":
                    failures.append(f"{name}: a hidden, independently writable backing remains")
            elif name == "held-legacy-filefd-append":
                incumbent = CANONICAL / "incumbent"
                if not incumbent.is_file() or b"old-file-fd\n" not in incumbent.read_bytes():
                    failures.append(f"{name}: stale writable file FD did not update canonical backing")
            else:
                failures.append(f"{name}: prohibited physical HOME entry was created")

    if os.path.lexists(LEGACY):
        failures.append("physical HOME still contains forbidden .legacy")
    if os.path.lexists(BLOCKED):
        failures.append("held HOME dirfd created forbidden .blocked")
        # Disposable VM only: remove failed probe output so EEXIST cannot
        # produce misleading denial in subsequent independent syscall probes.
        try:
            reset_blocked()
        except OSError as exc:
            raise RuntimeError(f"failed to reset already-proven bypass: errno={exc.errno}")

    for boundary, findings in (("unwrapped-host", user_run()), ("separate-mount-namespace", user_run(True))):
        for finding in findings:
            if finding["label"] == "canonical-writer":
                if finding["result"] != "allowed":
                    failures.append(f"{boundary}: authorized writer broken")
            elif finding["result"] != "denied":
                failures.append(f"{boundary}/{finding['label']}: {finding['result']} errno={finding.get('errno')}")

    verdict = {"decision": "FAIL" if failures else "PASS", "held_fd": held, "violations": failures}
    print(json.dumps(verdict, indent=2), flush=True)
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) == 2 else None
    if command == "hold":
        hold()
    elif command == "verify":
        verify()
    elif command == "unwrapped":
        print(json.dumps(direct_probes()))
    else:
        raise SystemExit("usage: seal-acceptance.py {hold|verify|unwrapped}")
