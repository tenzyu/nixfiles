from __future__ import annotations

import os
import signal
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass, field

from .config import Error


def run(argv, timeout=10, env=None, *, allowed_codes=(0,)):
    with tempfile.TemporaryFile() as output:
        try:
            child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=output,
                                     stderr=output, env=env, start_new_session=True)
        except OSError:
            raise Error(f"Cannot execute {os.path.basename(argv[0])}; install the required capability") from None
        try:
            code = child.wait(timeout)
        except subprocess.TimeoutExpired:
            terminate(child)
            raise Error(f"{os.path.basename(argv[0])} timed out; check the service or device") from None
        output.seek(0)
        result = output.read(2 * 1024 * 1024 + 1)
        if code not in allowed_codes or len(result) > 2 * 1024 * 1024:
            raise Error(f"{os.path.basename(argv[0])} probe failed; check its capabilities and device access")
        return result.decode("utf-8", errors="replace")


def terminate(child):
    # The leader may already have exited while its process group still owns children.
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            pass
        if sig == signal.SIGTERM:
            try:
                child.wait(2)
            except subprocess.TimeoutExpired:
                pass
    child.wait()


@dataclass
class Child:
    name: str
    argv: list[str]
    process: subprocess.Popen
    env: dict | None
    progress: dict = field(default_factory=dict)
    updated: float = 0
    attempts: int = 0


class Processes:
    def __init__(self):
        self.children: dict[str, Child] = {}
        self.cleanups = []

    def spawn(self, name, argv, env=None):
        if name in self.children:
            raise Error(f"{name} is already owned by this session")
        try:
            process = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, start_new_session=True, bufsize=0)
        except OSError:
            raise Error(f"Cannot start {name}; run doctor") from None
        child = Child(name, list(argv), process, env)
        self.children[name] = child
        threading.Thread(target=self._drain, args=(child,), daemon=True).start()
        return child

    @staticmethod
    def _drain(child):
        stream = child.process.stdout
        try:
            while line := stream.readline(4096):
                text = line.decode(errors="replace").strip()
                key, _, value = text.partition("=")
                if key in {"out_time_us", "frame", "total_size", "progress"}:
                    if key == "out_time_us" and value != child.progress.get(key):
                        child.updated = time.monotonic()
                    child.progress[key] = value
        finally:
            stream.close()

    def stop(self, name):
        child = self.children.pop(name, None)
        if child:
            terminate(child.process)

    def restart(self, name, limit):
        child = self.children[name]
        if child.attempts >= limit:
            raise Error(f"{name} exhausted retries; stop, run doctor, then prepare")
        self.stop(name)
        new = self.spawn(name, child.argv, child.env)
        new.attempts = child.attempts + 1

    def close(self):
        for name in list(self.children)[::-1]:
            self.stop(name)
        errors = []
        for cleanup in self.cleanups[::-1]:
            try:
                cleanup()
            except Error:
                errors.append("Owned audio route cleanup failed; inspect pactl list modules")
        self.cleanups.clear()
        return errors

    def status(self):
        return [{"name": c.name, "pid": c.process.pid, "alive": c.process.poll() is None,
                 "exit_code": c.process.poll(), "retries": c.attempts} for c in self.children.values()]


def wait_for(check, timeout, message, processes=None):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if processes and any(c.process.poll() is not None for c in processes.children.values()):
            raise Error("A session child exited during readiness; run doctor")
        try:
            result = check()
            if result:
                return result
        except (Error, OSError):
            pass
        time.sleep(0.15)
    raise Error(message)
