#!/usr/bin/env python3
"""Independent, fail-closed Direct Scanout/KMS capture acceptance test.

Nothing is installed, escalated, killed by pattern, or changed in the WM.
Only child processes started by this tool are stopped by this tool.
"""
from __future__ import annotations
import argparse
from collections import Counter
from scanout import classify, scanout_value, monitor_snapshot
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time

LOCAL_PORT = 11935
REMOTE_PORT = 11935

def gsr_targets() -> str:
    p = subprocess.run(["gpu-screen-recorder", "--list-capture-options"],
                       capture_output=True, text=True, timeout=12)
    if p.returncode != 0:
        raise RuntimeError(f"GSR target query failed: {p.stderr.strip()[:500]}")
    return p.stdout + "\n" + p.stderr

def build_gsr(args: argparse.Namespace) -> list[str]:
    cmd = ["gpu-screen-recorder", "-w", args.monitor, "-f", str(args.fps),
           "-fm", "cfr", "-k", "h264", "-encoder", "gpu",
           "-fallback-cpu-encoding", "no", "-bm", "cbr",
           "-q", str(args.bitrate_kbps), "-keyint", str(args.keyint_seconds),
           "-cursor", "no"]
    if args.audio_app:
        cmd += ["-a", args.audio_app, "-ac", "aac", "-ab", "192"]
    cmd += ["-c", "flv", "-o", f"rtmp://127.0.0.1:{LOCAL_PORT}/game"]
    return cmd

def build_ssh(args: argparse.Namespace) -> list[str]:
    return ["ssh", "-N", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=yes", "-o", "ClearAllForwardings=yes",
            "-L", f"127.0.0.1:{LOCAL_PORT}:127.0.0.1:{REMOTE_PORT}", args.ssh_host]

def free_local_port(port: int) -> bool:
    with socket.socket() as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False

def wait_tunnel(p: subprocess.Popen, port: int, timeout=12.0) -> None:
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        if p.poll() is not None:
            raise RuntimeError(f"SSH tunnel terminated: exit={p.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.2)
    raise RuntimeError("SSH tunnel not ready; is remote MediaMTX running?")

class DirectScanoutLost(RuntimeError):
    def __init__(self, samples):
        super().__init__("Direct Scanout continuously absent for four samples; stopping capture")
        self.samples = samples

def sample_window(name: str, seconds: float, log, interval=0.25, observed_process=None):
    stop_at = time.monotonic() + seconds
    samples = []
    failures_in_row = 0
    while time.monotonic() < stop_at:
        if observed_process is not None and observed_process.poll() is not None:
            raise RuntimeError(f"GSR stopped unexpectedly: exit={observed_process.returncode}")
        row = monitor_snapshot(name)
        row["phase"] = "baseline" if observed_process is None else "capture"
        log.write(json.dumps(row, ensure_ascii=False) + "\n")
        log.flush()
        samples.append(row)
        if observed_process is not None:
            failures_in_row = 0 if row["direct"] is True else failures_in_row + 1
            if failures_in_row >= 4:
                raise DirectScanoutLost(samples)
        time.sleep(interval)
    return samples

def stop_child(p: subprocess.Popen | None, soft: int = signal.SIGTERM) -> None:
    if p is None or p.poll() is not None:
        return
    os.killpg(p.pid, soft)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait(timeout=5)

def ratio_true(samples) -> float:
    return sum(r["direct"] is True for r in samples) / max(len(samples), 1)

def parse(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--monitor", default="eDP-1", help="Physical monitor name (never portal)")
    ap.add_argument("--ssh-host", default="neko7", help="Existing trusted SSH alias")
    ap.add_argument("--fps", type=int, choices=(30, 60), default=60)
    ap.add_argument("--bitrate-kbps", type=int, default=12000)
    ap.add_argument("--keyint-seconds", type=int, default=1)
    ap.add_argument("--audio-app", default="", help="Exact GSR app: name, e.g. app:osu!; optional")
    ap.add_argument("--focus-seconds", type=int, default=8)
    ap.add_argument("--baseline-seconds", type=int, default=4)
    ap.add_argument("--capture-seconds", type=int, default=16)
    ap.add_argument("--warmup-seconds", type=int, default=2)
    ap.add_argument("--output-dir", type=Path,
                    default=Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "directcast-lab")
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args(argv)

def main(argv=None) -> int:
    args = parse(argv)
    if args.monitor in ("screen", "portal", "focused", "region") or any(c in args.monitor for c in "|;:/"):
        raise ValueError("A specific physical monitor name is required; portal or dynamic targets forbidden")
    if args.audio_app and (not args.audio_app.startswith("app:") or any(c in args.audio_app for c in "\r\n|;")):
        raise ValueError("--audio-app must be an exact app:NAME selector")
    if not 1000 <= args.bitrate_kbps <= 50000 or not 1 <= args.keyint_seconds <= 5:
        raise ValueError("bitrate/keyint out of lab bounds")
    if not (args.focus_seconds >= 3 and args.capture_seconds >= 5 and args.baseline_seconds >= 2):
        raise ValueError("invalid sampling duration")
    cmd, ssh_cmd = build_gsr(args), build_ssh(args)
    print("GSR:", json.dumps(cmd, ensure_ascii=False))
    print("SSH:", json.dumps(ssh_cmd, ensure_ascii=False))
    print("Receiver: 127.0.0.1:11935 RTMP → 127.0.0.1:18554 RTSP on neko7")
    if args.dry_run:
        return 0
    for executable in ("gpu-screen-recorder", "hyprctl", "ssh"):
        if not shutil.which(executable):
            raise RuntimeError(f"missing executable: {executable}")
    options = gsr_targets()
    if args.monitor not in {ln.strip().split("|")[0].strip() for ln in options.splitlines()}:
        raise RuntimeError(f"GSR does not advertise {args.monitor!r}; run --list-capture-options")
    if not free_local_port(LOCAL_PORT):
        raise RuntimeError(f"local TCP {LOCAL_PORT} is occupied; no existing instance will be disrupted")
    probe = monitor_snapshot(args.monitor)
    if probe["direct"] is None:
        raise RuntimeError("hyprctl direct scanout fields are unavailable; cannot certify the invariant")
    directory = args.output_dir / datetime.now().strftime("%Y%m%d-%H%M%S")
    directory.mkdir(parents=True, exist_ok=False)
    ssh, capture = None, None
    report = {"monitor": args.monitor, "recorded": False, "test": "incomplete", "samples": {},
              "commands": {"gsr": cmd, "ssh": ssh_cmd}, "output_dir": str(directory)}
    with (directory / "samples.jsonl").open("w", encoding="utf-8") as out, \
         (directory / "ssh.stderr.log").open("w", encoding="utf-8") as sshlog, \
         (directory / "gsr.stderr.log").open("w", encoding="utf-8") as gsrlog:
        try:
            ssh = subprocess.Popen(ssh_cmd, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=sshlog, start_new_session=True)
            wait_tunnel(ssh, LOCAL_PORT)
            print(f"Switch to osu! fullscreen now. Starting baseline in {args.focus_seconds} s", flush=True)
            time.sleep(args.focus_seconds)
            before = sample_window(args.monitor, args.baseline_seconds, out)
            report["samples"]["baseline"] = {
                "count": len(before), "fraction": ratio_true(before),
                "states": dict(Counter(str(s["direct"]) for s in before))}
            if ratio_true(before) < .90:
                raise RuntimeError("baseline Direct Scanout <90%; ensure osu! is fullscreen before capture")
            print("Baseline direct; starting GSR for monitored capture", flush=True)
            capture = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.DEVNULL, stderr=gsrlog, start_new_session=True)
            time.sleep(args.warmup_seconds)
            during = sample_window(args.monitor, args.capture_seconds, out,
                                   observed_process=capture)
            report["samples"]["capture"] = {
                "count": len(during), "fraction": ratio_true(during),
                "states": dict(Counter(str(s["direct"]) for s in during))}
            if ratio_true(during) < .95:
                raise RuntimeError("Direct Scanout dropped below 95% while capturing: reject this path")
            report["recorded"] = True
            report["test"] = "PASS: Direct Scanout observed during capture (not an end-to-end latency measurement)"
            print(report["test"], flush=True)
            return 0
        except DirectScanoutLost as exc:
            report["samples"]["capture"] = {
                "count": len(exc.samples), "fraction": ratio_true(exc.samples),
                "states": dict(Counter(str(s["direct"]) for s in exc.samples)),
                "early_abort": True}
            report["test"] = "FAIL: " + str(exc)
            print(report["test"], file=sys.stderr, flush=True)
            return 3
        except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
            report["test"] = "FAIL: " + str(exc)
            print(report["test"], file=sys.stderr, flush=True)
            return 3
        finally:
            stop_child(capture, signal.SIGINT)
            stop_child(ssh, signal.SIGTERM)
            (directory / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print("Report:", directory / "report.json", flush=True)

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, RuntimeError, OSError) as ex:
        print("Preflight failed:", ex, file=sys.stderr)
        sys.exit(2)
