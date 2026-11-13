#!/usr/bin/env python3
"""Per-process timer slack for osu!: optional hint, never modifies the game."""
from __future__ import annotations

import argparse
import ctypes
import os
import sys

PR_SET_TIMERSLACK = 29
PR_GET_TIMERSLACK = 30


def apply_timer_slack(ns: int) -> int:
    if sys.platform != "linux":
        raise RuntimeError("PR_SET_TIMERSLACK is only supported on Linux")
    if not 1 <= ns <= 50_000:
        raise ValueError("--nanoseconds must be between 1 and 50000")
    libc = ctypes.CDLL(None, use_errno=True)
    prctl = libc.prctl
    prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
    prctl.restype = ctypes.c_int
    if prctl(PR_SET_TIMERSLACK, ns, 0, 0, 0) != 0:
        err = ctypes.get_errno()
        raise OSError(err, f"prctl(PR_SET_TIMERSLACK, {ns}) failed: {os.strerror(err)}")
    actual = prctl(PR_GET_TIMERSLACK, 0, 0, 0, 0)
    if actual == -1:
        err = ctypes.get_errno()
        raise OSError(err, f"prctl(PR_GET_TIMERSLACK) failed: {os.strerror(err)}")
    if actual != ns:
        raise RuntimeError(f"timer slack requested {ns} ns; kernel returned {actual} ns")
    return actual


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run a command with optional per-process Linux timer slack")
    parser.add_argument("--nanoseconds", type=int, required=True, help="1..50000 ns")
    parser.add_argument("--best-effort", action="store_true", help="continue without override if prctl fails")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="-- osu-lazer [args]")
    args = parser.parse_args(argv)
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("missing command; use -- osu-lazer")
    if not 1 <= args.nanoseconds <= 50_000:
        parser.error("--nanoseconds must be between 1 and 50000")
    try:
        actual = apply_timer_slack(args.nanoseconds)
    except (OSError, RuntimeError, ValueError) as error:
        if not args.best_effort:
            print(f"timerslack-exec: {error}; command NOT launched", file=sys.stderr)
            return 1
        print(f"timerslack-exec: {error}; proceeding without timer override", file=sys.stderr)
    else:
        print(f"timerslack-exec: per-process slack={actual} ns; not a guaranteed frame-time improvement", file=sys.stderr)
    try:
        os.execvp(command[0], command)
    except OSError as error:
        print(f"timerslack-exec: exec failed: {error}", file=sys.stderr)
        return 127
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
