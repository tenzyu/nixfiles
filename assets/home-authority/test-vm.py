#!/usr/bin/env python3
"""VM-only probes: successes and deliberately failing whole-HOME guarantees.

Never use this script on a production HOME. No migration code is implemented.
"""
import os
import pathlib
import shutil
import stat
import subprocess
import sys

HOME = pathlib.Path("/home/fixture")
CANONICAL = HOME / ".local/share/authority"
LEGACY = HOME / ".legacy"
REPORT = HOME / ".local/state/nixfiles/home-authority-report.txt"


def run(*argv, check=True):
    return subprocess.run(argv, text=True, capture_output=True, check=check)


def expect_denied(call, label):
    try:
        call()
    except OSError as error:
        assert error.errno in (1, 13, 30), (label, error)
        return
    raise AssertionError(f"{label}: forbidden write unexpectedly succeeded")


def audit_initial():
    text = REPORT.read_text()
    assert "mode=observe" in text, text
    assert "EMPTY: verify this is a new app" in text, text
    assert not LEGACY.exists()
    assert REPORT.stat().st_mode & 0o077 == 0, "report disclosed fixture metadata"
    print("PASS: native Home Manager activation reports without moving state")


def make_conflict():
    CANONICAL.mkdir(parents=True, exist_ok=True)
    LEGACY.mkdir()
    CANONICAL.joinpath("current").write_text("canonical\n")
    LEGACY.joinpath("old").write_text("legacy\n")
    os.chown(CANONICAL, 1000, 100)
    os.chown(LEGACY, 1000, 100)


def check_conflict():
    text = REPORT.read_text()
    assert "CONFLICT: retain incumbent" in text, text
    assert (CANONICAL / "current").read_text() == "canonical\n"
    assert (LEGACY / "old").read_text() == "legacy\n"
    shutil.rmtree(LEGACY)
    print("PASS: conflict report preserves both independent copies")


def bound_view_and_old_dirfd():
    LEGACY.mkdir()
    old_fd = os.open(LEGACY, os.O_RDONLY | os.O_DIRECTORY)
    try:
        run("mount", "--bind", str(CANONICAL), str(LEGACY))
        try:
            assert os.stat(LEGACY).st_dev == os.stat(CANONICAL).st_dev
            assert os.stat(LEGACY).st_ino == os.stat(CANONICAL).st_ino
            run("runuser", "-u", "fixture", "--", "sh", "-c",
                'printf shell > "$HOME/.legacy/from-shell"')
            run("systemctl", "start", "home-authority-fixture-writer.service")
            assert (CANONICAL / "from-shell").read_text() == "shell"
            assert (LEGACY / "from-service").read_text() == "service\n"

            # Negative control: a pre-bind directory FD still owns the hidden
            # original directory, even while both *names* expose one inode.
            stale = os.open("split-brain", os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                            0o600, dir_fd=old_fd)
            os.write(stale, b"hidden independent writer")
            os.close(stale)
            assert not (LEGACY / "split-brain").exists()
            print("GAP CONFIRMED: pre-bind directory FD writes hidden backing")
        finally:
            run("umount", str(LEGACY))
    finally:
        os.close(old_fd)
    assert (LEGACY / "split-brain").read_bytes() == b"hidden independent writer"
    shutil.rmtree(LEGACY)
    print("PASS: native shell and systemd service see same bind-backed inode")


def readonly_view_does_not_seal_host():
    # A read-only namespace view does not affect a process that retains
    # the original mount namespace and can still mutate physical HOME.
    inner = (
        "set -eu; "
        "mount --bind /home/fixture /home/fixture; "
        "mount -o remount,bind,ro /home/fixture; "
        "! touch /home/fixture/.legacy"
    )
    result = run("unshare", "--mount", "--propagation", "private",
                 "sh", "-c", inner, check=False)
    assert result.returncode == 0, result.stderr
    LEGACY.write_text("unwrapped host created banned entry\n")
    assert LEGACY.exists()
    LEGACY.unlink()
    print("GAP CONFIRMED: read-only sandbox view does not protect physical HOME")


def immutable_root_and_open_fd():
    # A candidate chattr policy may forbid new names but cannot revoke
    # writes through an already-open writable file handle.
    legacy = LEGACY
    legacy.write_text("before\n")
    fd = os.open(legacy, os.O_WRONLY | os.O_APPEND)
    parent_fd = os.open(HOME, os.O_RDONLY | os.O_DIRECTORY)
    example = CANONICAL / "to-rename"
    example.write_text("state\n")
    result = run("chattr", "+i", str(HOME), check=False)
    if result.returncode != 0:
        print(f"UNSUPPORTED: immutable directory on VM filesystem: {result.stderr.strip()}")
        os.close(fd)
        os.close(parent_fd)
        legacy.unlink()
        return
    try:
        def create_through_old_dir():
            descriptor = os.open(".another", os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                                 0o600, dir_fd=parent_fd)
            os.close(descriptor)
        expect_denied(create_through_old_dir, "openat on pre-opened HOME dir")
        expect_denied(lambda: os.rename(example, HOME / ".another"), "rename into HOME")
        expect_denied(lambda: os.link(example, HOME / ".another"), "hardlink into HOME")
        expect_denied(lambda: HOME.joinpath(".another").write_text("restored"), "copy/restore into HOME")

        # This MUST remain a negative control, not a passing root-authority claim.
        assert os.write(fd, b"after-seal\n") == len(b"after-seal\n")
        assert "after-seal" in legacy.read_text()
        print("GAP CONFIRMED: immutable HOME does not revoke an open file FD")
        print("PASS: immutable directory rejects direct create/rename/link/restore")
    finally:
        run("chattr", "-i", str(HOME))
        os.close(fd)
        os.close(parent_fd)
        legacy.unlink()


ACTIONS = {
    "audit": audit_initial,
    "seed-collision": make_conflict,
    "check-collision": check_conflict,
    "bind": bound_view_and_old_dirfd,
    "readonly-view": readonly_view_does_not_seal_host,
    "immutable": immutable_root_and_open_fd,
}

if __name__ == "__main__":
    assert len(sys.argv) == 2 and sys.argv[1] in ACTIONS
    ACTIONS[sys.argv[1]]()
