"""Exercise the packaged operator and writer against isolated policy and mocks."""

import os
import shutil
import signal
import stat
import subprocess
import sys
import time
from pathlib import Path

operator, root, identity, tar = sys.argv[1:]
root = Path(root)
control = root / "control"
source = root / "data/survival"
destination = root / "data/backups"
lock = root / "run/minecraft.lock"
final = destination / "minecraft-20261119-113355.tar.gz"
world = b"minecraft world fixture\x00\xff"
real = identity == "real"
archive_uid = 27009 if real else os.geteuid()
archive_gid = 27009 if real else os.getegid()


def set_control(name: str, value: str) -> None:
    path = control / name
    path.write_text(value)
    path.chmod(0o644)


def setup(guest: str = "running", host: str = "running") -> None:
    root.mkdir(mode=0o755, exist_ok=True)
    root.chmod(0o755)
    for name in ("run", "control", "data", "restore", "outside"):
        path = root / name
        if path.exists():
            shutil.rmtree(path)
        path.mkdir()
    control.chmod(0o755)
    if real:
        os.chown(control, archive_uid, archive_gid)
    lock.parent.chmod(0o750)
    lock.touch()
    lock.chmod(0o440)
    source.mkdir()
    (source / "world/region").mkdir(parents=True)
    (source / "world/level.dat").write_bytes(world)
    (source / "world/region/r.0.0.mca").write_bytes(b"region data")
    (source / "server.properties").write_text("fixture config")
    (source.parent / "secrets").write_text("outside the backup root")
    destination.mkdir(mode=0o750)
    for path in (source.parent, source, *source.rglob("*"), destination):
        os.chown(path, archive_uid, archive_gid)
    for name, value in {
        "events": "", "host": host, "guest": guest, "stop": "inactive",
        "resume": "running", "io": "ok", "transition": "inherit", "admin": "normal",
    }.items():
        set_control(name, value)
    (control / "events").chmod(0o666)


def run(action: str, *args: str, status: int = 0, output: str = ""):
    result = subprocess.run([operator, action, *args], capture_output=True, text=True, timeout=10)
    report = result.stdout + result.stderr
    assert result.returncode == status, (action, status, result.returncode, report, events())
    assert output in report, report
    return result


def events() -> list[str]:
    return (control / "events").read_text().splitlines()


def guest_state() -> str:
    return (control / "guest").read_text()


def no_publication():
    assert not final.exists() and not final.is_symlink(), list(destination.iterdir())
    assert not list(destination.glob(".safety-stage.*")), list(destination.iterdir())


def observe(path: Path):
    info = path.lstat()
    payload = os.readlink(path) if path.is_symlink() else sorted(path.iterdir()) if path.is_dir() else path.read_bytes()
    return info.st_ino, info.st_mode, payload


def wait_ready(name: str):
    for _ in range(500):
        if (control / f"{name}-ready").exists():
            return
        time.sleep(0.01)
    raise AssertionError(f"{name} did not reach fixture barrier: {events()}")


def start(action: str, *args: str):
    return subprocess.Popen([operator, action, *args], start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def await_result(process, status):
    out, err = process.communicate(timeout=10)
    assert process.returncode == status, (process.returncode, status, out, err, events())


setup()
old = destination / "minecraft-20261119-113354.tar.gz"
old.write_bytes(b"previous archive")
old.chmod(0o640)
old_info = observe(old)
identity_before = lock.stat().st_ino
result = run("backup", output="Resume: guest running")
assert "Archive: published" in result.stdout
assert guest_state() == "running"
assert observe(old) == old_info
assert lock.stat().st_ino == identity_before
assert stat.S_IMODE(final.stat().st_mode) == 0o600
assert (final.stat().st_uid, final.stat().st_gid) == (archive_uid, archive_gid)
assert [step for step in events() if step in ("guest stop", "tar", "file-sync", "link", "directory-sync", "guest start")] == [
    "guest stop", "tar", "file-sync", "link", "directory-sync", "guest start"
]
if not real:
    assert events().index("writer preflight") < events().index("guest stop")
subprocess.run([tar, "-xzf", str(final), "-C", str(root / "restore"), "--no-same-owner"], check=True)
assert sorted(x.name for x in (root / "restore").iterdir()) == ["survival"]
restored = root / "restore/survival"
assert (restored / "world/level.dat").read_bytes() == world
assert (restored / "world/region/r.0.0.mca").read_bytes() == b"region data"
new_info = observe(final)
scope_inode = (destination / ".safety.lock").stat().st_ino
run("backup", status=73, output="backup refused before stop")
assert observe(final) == new_info and observe(old) == old_info
assert events().count("guest stop") == 1 and guest_state() == "running"
assert (destination / ".safety.lock").stat().st_ino == scope_inode
print("PUBLISH-01: ordered publish, restore, numeric ownership, and same-second no-clobber")

for kind in ("directory", "dangling", "symlink"):
    setup()
    if kind == "directory":
        final.mkdir()
        (final / "occupant").write_bytes(b"untouched")
    elif kind == "dangling":
        final.symlink_to(root / "missing")
    else:
        final.symlink_to(root / "outside", target_is_directory=True)
    old_state = observe(final)
    run("backup", status=73, output="already exists")
    assert observe(final) == old_state and "guest stop" not in events()
    assert list((root / "outside").iterdir()) == []

setup(guest="inactive")
run("backup", output="Resume: unnecessary")
assert final.is_file() and "guest stop" not in events() and "guest start" not in events()
assert "host start" not in events()
setup(host="inactive")
run("backup", status=69, output="container must already be running")
run("status", output="container inactive / guest state unavailable")
assert all(e == "host show" for e in events())
no_publication()

for initial in ("unknown", "failed", "missing", "transition", "running-job", "unclean", "inactive-tasks"):
    setup(guest=initial)
    run("backup", status=69, output="before stop")
    assert guest_state() == initial and "guest stop" not in events() and "tar" not in events()
    no_publication()

for issue in ("missing-source", "group-writable", "symlink-destination", "missing-world", "unsafe-scope-lock"):
    setup()
    if issue == "missing-source":
        source.rename(source.with_name("elsewhere"))
    elif issue == "group-writable":
        destination.chmod(0o770)
    elif issue == "symlink-destination":
        destination.rmdir()
        destination.symlink_to(root / "outside")
    elif issue == "missing-world":
        (source / "world/level.dat").unlink()
    else:
        (destination / ".safety.lock").symlink_to(root / "outside")
    run("backup", status=74 if issue in ("missing-source", "missing-world") else 69, output="backup refused before stop")
    assert "guest stop" not in events() and guest_state() == "running"

for inaccessible in ("mode", "missing", "symlink"):
    setup()
    if inaccessible == "mode":
        lock.chmod(0o660)
    else:
        lock.unlink()
        if inaccessible == "symlink":
            lock.symlink_to(root / "outside")
    run("backup", status=69, output="native root:wheel")
    assert events() == []

if not real:
    setup()
    set_control("transition", "drop-fd")
    run("backup", status=69, output="descriptor did not survive")
    assert "guest stop" not in events()
print("BOUNDARY-01 / INTENT-01: stable policy inode, UID transition, preflight, and strict state refusals")

for stop_behavior, status in (("unknown", 31), ("unclean", 69), ("inactive-tasks", 69), ("transition", 69)):
    setup()
    set_control("stop", stop_behavior)
    run("backup", status=status, output="Archive: not attempted")
    assert "guest stop" in events() and "tar" not in events() and "guest start" not in events()
    no_publication()

for fault, status in (("enospc", 28), ("bad-gzip", 1), ("bad-tar", 2), ("missing-world", 69),
                      ("file-sync", 74), ("link", 74), ("directory-sync", 74)):
    setup()
    set_control("io", fault)
    result = run("backup", status=status, output="Archive: no new publication" if fault in (
        "enospc", "bad-gzip", "bad-tar", "missing-world"
    ) else "Archive: unconfirmed")
    assert "Resume: skipped" in result.stderr and "guest start" not in events()
    assert guest_state() == "inactive"
    if fault == "directory-sync":
        assert "OutcomeUnknown" in result.stderr
        assert final.is_file() and len(list(destination.glob(".safety-stage.*"))) == 1
    else:
        no_publication()

for state, status in (("return-failure", 32), ("failed", 69)):
    setup()
    set_control("resume", state)
    result = run("backup", status=status, output="Resume: failed")
    assert "Archive: published" in result.stdout and final.is_file()
    if state == "return-failure":
        run("start", status=69, output="previous native job unconfirmed")
print("PUBLISH-02 / RECOVERY-01: clean stop evidence, I/O failures, uncertain sync and separate resume result")

setup()
set_control("io", "block")
process = start("backup")
try:
    wait_ready("tar")
    assert guest_state() == "inactive"
    run("start", status=73, output="lifecycle lock")
    # The stage producer still holds the same open-file-description flock
    # after killing the coordinator, including real setpriv in namespace mode.
    process.kill()
    run("restart", status=73, output="lifecycle lock")
    set_control("tar-release", "")
    await_result(process, -signal.SIGKILL)
    assert guest_state() == "inactive" and final.is_file()
    run("start", output="")
finally:
    set_control("tar-release", "")
    if process.poll() is None:
        process.kill()
        process.communicate(timeout=10)

# Cause a final-leaf collision after preflight and staging.
setup()
set_control("io", "block")
process = start("backup")
try:
    wait_ready("tar")
    final.write_bytes(b"concurrent archive")
    final_info = observe(final)
    set_control("tar-release", "")
    await_result(process, 73)
    assert observe(final) == final_info and guest_state() == "inactive"
    assert not list(destination.glob(".safety-stage.*"))
finally:
    set_control("tar-release", "")

setup()
set_control("stop", "block")
process = start("backup")
try:
    wait_ready("stop")
    os.killpg(process.pid, signal.SIGTERM)
    run("send", "list", status=73, output="lifecycle lock")
    set_control("stop-release", "")
    await_result(process, 143)
    assert guest_state() == "inactive" and "tar" not in events()
    no_publication()
finally:
    set_control("stop-release", "")

setup()
set_control("stop", "block")
process = start("backup")
wait_ready("stop")
os.killpg(process.pid, signal.SIGKILL)
await_result(process, -signal.SIGKILL)
run("start", status=69, output="previous native job unconfirmed")
assert lock.with_suffix(".lock.job").is_dir() and guest_state() == "running"

setup()
set_control("admin", "block")
process = start("exec", "some-admin-command")
try:
    wait_ready("admin")
    run("backup", status=73, output="lifecycle lock")
    set_control("admin-release", "")
    await_result(process, 0)
finally:
    set_control("admin-release", "")
print(f"LOCK-01: managed contention across coordinator kill, waiter interruption and {identity} UID transition")
