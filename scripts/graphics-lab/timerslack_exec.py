#!/usr/bin/env python3
"""Run a child process with specified Linux timer slack (nanoseconds).

Usage: python3 osu-timerslack-exec.py 1 ./osu-lazer-test.sh sdl3-wayland-gl ./osu.AppImage
Reset by launching osu! normally. This affects only the new process and its threads.
"""
import ctypes
import os
import sys

PR_SET_TIMERSLACK = 29


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: osu-timerslack-exec.py NANOSECONDS COMMAND [ARGS...]")
    try:
        slack_ns = int(sys.argv[1])
    except ValueError as exc:
        raise SystemExit("NANOSECONDS must be a positive integer") from exc
    if not 1 <= slack_ns <= 1_000_000_000:
        raise SystemExit("NANOSECONDS must be in [1, 1000000000]")

    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl.argtypes = (
        ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
        ctypes.c_ulong, ctypes.c_ulong,
    )
    libc.prctl.restype = ctypes.c_int
    if libc.prctl(PR_SET_TIMERSLACK, slack_ns, 0, 0, 0) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))

    os.execvp(sys.argv[2], sys.argv[2:])


if __name__ == "__main__":
    main()
