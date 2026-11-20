#!/usr/bin/env python3
"""Read-only Linux/Hyprland/PipeWire osu! telemetry. No game/firmware modifications.

The output deliberately distinguishes measured, proxy and unobservable quantities.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import html
import json
import math
import os
import re
import selectors
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
from collections import Counter
from contextlib import contextmanager
from pathlib import Path

VERSION = "2026-11-20.2"
EVENT = struct.Struct("@llHHi")  # struct input_event on native 64-bit Linux
EVIOCSCLOCKID = 0x400445A0  # _IOW('E', 0xA0, int), CLOCK_MONOTONIC=1
MONITOR = "eDP-1"
PATHS = [Path.home() / ".local/share/osu", Path.home() / ".local/share/osu-lazer", Path.home() / ".config/osu"]
PERF_FILES = {"performance-input.log", "performance-update.log", "performance-draw.log", "performance-audio.log"}
SENSITIVE = {"OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD", "SDL_VIDEODRIVER", "PIPEWIRE_LATENCY"}
STOP = None
INPUT_COUNTS = ("key_up", "key_down", "key_repeat", "pen_touch_up", "pen_touch_down")
MONOTONIC = "CLOCK_MONOTONIC"
INCOMPLETE = "capture-incomplete"
PW_ERR_SOURCE = "pw-top same observed node ID and nondecreasing ERR samples"


def stamp():
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def write_file(path, content, *, new=False):
    # Replacing the directory entry prevents following a symlink or writing through a hard link.
    out = tempfile.NamedTemporaryFile(dir=path.parent, delete=False)
    staged = Path(out.name)
    try:
        with out:
            out.write(content.encode("utf-8") if isinstance(content, str) else content)
            out.flush()
            os.fsync(out.fileno())
        if new:
            os.link(staged, path)
        else:
            os.replace(staged, path)
    finally:
        staged.unlink(missing_ok=True)


def write_json(path, data, *, new=False):
    write_file(path, json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n", new=new)


def read(path):
    try:
        return Path(path).read_text(errors="replace").strip()
    except (OSError, ValueError):
        return None


def command(args, timeout=1.2, parse_json=False):
    if not shutil.which(args[0]):
        return None
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
        if p.returncode != 0:
            return None
        return json.loads(p.stdout) if parse_json else p.stdout.strip()
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def percentile(values, p):
    if not values:
        return None
    values = sorted(values)
    x = (len(values) - 1) * p / 100.0
    lo, hi = math.floor(x), math.ceil(x)
    return round(values[lo] + (values[hi] - values[lo]) * (x - lo), 4)


def dist(values):
    return {"count": len(values), "min": percentile(values, 0),
            "p50": percentile(values, 50), "p95": percentile(values, 95),
            "p99": percentile(values, 99), "p99_9": percentile(values, 99.9),
            "max": percentile(values, 100)}


def node_candidates():
    """Collect only identifiable tablet / keypad interfaces, no general keyboard snooping."""
    found = []
    for sysnode in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
        uevent = read(sysnode / "device/uevent") or ""
        name = next((l[9:] for l in uevent.splitlines() if l.startswith("HID_NAME=")), "")
        identity = next((l[7:] for l in uevent.splitlines() if l.startswith("HID_ID=")), "")
        if re.search(r"wacom|ctl.?472", name, re.I) or ":0000056A:" in identity.upper():
            found.append({"kind": "hidraw", "path": "/dev/" + sysnode.name, "name": name, "id": identity, "auto": True})
    for sysnode in sorted(Path("/sys/class/input").glob("event*")):
        name = read(sysnode / "device/name") or ""
        if re.search(r"sayo|o3c|wacom|ctl.?472", name, re.I):
            found.append({"kind": "evdev", "path": "/dev/input/" + sysnode.name, "name": name, "auto": True})
    return found


class InputObserver:
    def __init__(self, override_hidraw=None, override_event=None):
        devs = node_candidates()
        for kind, overrides in (("hidraw", override_hidraw or []), ("evdev", override_event or [])):
            for device in overrides:
                if not re.fullmatch(r"/dev/hidraw\d+" if kind == "hidraw" else r"/dev/input/event\d+", device):
                    raise ValueError(f"unsafe device path: {device}")
                if not any(d["path"] == device for d in devs):
                    devs.append({"kind": kind, "path": device, "name": "manual selection", "auto": False})
        self.selector = selectors.DefaultSelector()
        self.owned = {}
        self.devices = []
        self.status = []
        try:
            for device in devs:
                self.open_device(device)
        except BaseException:
            self.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        self.close()

    def open_device(self, device):
        d = {**device, **dict.fromkeys(INPUT_COUNTS, 0), "reads": 0, "reports": 0, "syn_dropped": 0,
             "read_intervals_ms": [], "event_intervals_ms": [], "dispatch_delay_ms": [],
             "last_read_ns": None, "last_event_ns": None, "tail": b"", "pending": Counter(),
             "discarding": False, "in_frame": False, "read_ended": False, "kernel_clock": None}
        fd = None
        try:
            fd = os.open(d["path"], os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            self.owned[fd] = d
            if d["kind"] == "evdev":
                try:
                    fcntl.ioctl(fd, EVIOCSCLOCKID, struct.pack("i", time.CLOCK_MONOTONIC))
                    d["kernel_clock"] = MONOTONIC
                except OSError as e:
                    d["kernel_clock"] = f"unavailable ({e.strerror})"
            self.selector.register(fd, selectors.EVENT_READ, d)
        except OSError as e:
            if fd is not None:
                self.close_device(fd)
            self.status.append({**device, "status": f"unavailable: {e.strerror}"})
            return
        self.devices.append(d)
        self.status.append({**device, "status": "opened", "clock": d["kernel_clock"]})

    def close_device(self, fd):
        self.owned.pop(fd)
        try:
            self.selector.unregister(fd)
        except (KeyError, OSError):
            pass
        finally:
            # Linux releases the FD even if close reports an error. A retry could close a reused FD.
            try:
                os.close(fd)
            except OSError as e:
                self.status.append({"status": f"close error: {e.strerror}"})

    def close(self):
        if self.selector is None:
            return
        try:
            for fd in list(self.owned):
                self.close_device(fd)
        finally:
            self.selector.close()
            self.selector = None

    def sample(self, timeout):
        for key, _mask in self.selector.select(timeout):
            d = key.data
            try:
                chunk = os.read(key.fd, 8192)
            except BlockingIOError:
                continue
            except OSError as e:
                status = f"read error: {e.strerror}"
            else:
                if chunk:
                    now = time.monotonic_ns()
                    self.mark(d, now, "last_read_ns", "read_intervals_ms")
                    d["reads"] += 1
                    if d["kind"] == "hidraw":
                        # Each successful hidraw read returns one report.
                        d["reports"] += 1
                    else:
                        self.consume_events(d, chunk, now)
                    continue
                status = "end of file"
            self.status.append({"path": d["path"], "status": status})
            d["read_ended"] = True
            self.close_device(key.fd)

    def consume_events(self, d, chunk, now):
        packets = d["tail"] + chunk
        boundary = len(packets) - len(packets) % EVENT.size
        d["tail"] = packets[boundary:]
        for sec, usec, typ, code, value in EVENT.iter_unpack(packets[:boundary]):
            sync = typ == 0 and code == 0  # SYN_REPORT
            if typ == 0 and code == 3:  # SYN_DROPPED in this client's queue
                d["syn_dropped"] += 1
                d["pending"].clear()
                d["last_event_ns"] = None
                d["discarding"] = True
                d["in_frame"] = False
            elif d["discarding"]:
                if sync:
                    d["discarding"] = False  # The recovery boundary itself is discarded.
            elif sync:
                d["reports"] += 1
                for name, count in d["pending"].items():
                    d[name] += count
                d["pending"].clear()
                d["in_frame"] = False
                if d["kernel_clock"] == MONOTONIC and sec >= 0 and 0 <= usec < 1_000_000:
                    event_ns = (sec * 1_000_000 + usec) * 1_000
                    if event_ns <= now:
                        self.mark(d, event_ns, "last_event_ns", "event_intervals_ms")
                    else:
                        d["last_event_ns"] = None
                    if 0 <= now - event_ns < 5_000_000_000:
                        d["dispatch_delay_ms"].append((now - event_ns) / 1_000_000)
                else:
                    d["last_event_ns"] = None
            else:
                d["in_frame"] = True
                if typ == 1 and value in (0, 1, 2):
                    d["pending"][INPUT_COUNTS[value]] += 1
                    if code == 330 and value != 2:  # BTN_TOUCH
                        d["pending"][INPUT_COUNTS[3 + value]] += 1

    @staticmethod
    def mark(d, ns, previous, intervals):
        last = d[previous]
        if last is not None and ns > last:
            d[intervals].append((ns - last) / 1_000_000)
        d[previous] = ns

    def result(self):
        output = []
        for d in self.devices:
            hidraw = d["kind"] == "hidraw"
            aligned = d["kernel_clock"] == MONOTONIC
            periods = d["read_intervals_ms"] if hidraw else d["event_intervals_ms"]
            source = "hidraw read completion" if hidraw else "evdev SYN_REPORT"
            complete = not any((d["read_ended"], d["syn_dropped"], d["in_frame"], d["tail"]))
            output.append({**{key: d[key] for key in ("kind", "path", "name", "reports", "syn_dropped", *INPUT_COUNTS)},
                           "period_ms": dist(periods), "observer_delay_ms": dist(d["dispatch_delay_ms"]),
                           "histogram": histogram(periods, 0, 12, 0.5),
                           "read_interval_ms": dist(d["read_intervals_ms"]), "reads": d["reads"],
                           "timing": {"period_source": source, "period_clock": MONOTONIC if hidraw or aligned else None,
                                      "read_clock": MONOTONIC, "dispatch_clock": MONOTONIC if aligned else None},
                           "counts_complete": complete,
                           "interpretation": "hidraw userspace read intervals" if hidraw
                           else "evdev SYN_REPORT intervals (state changes, not fixed USB poll)"})
        return {"devices": output, "status": self.status}


def histogram(values, minimum, maximum, step):
    n = int(math.ceil((maximum - minimum) / step))
    counts = [0] * n
    overflow = 0
    for x in values:
        if minimum <= x < maximum:
            counts[min(int((x - minimum) / step), n - 1)] += 1
        else:
            overflow += 1
    return {"start": minimum, "step": step, "counts": counts, "outside_range": overflow}


def proc_pid(manual=None):
    if manual is not None:
        return manual if Path(f"/proc/{manual}").is_dir() else None
    match = []
    for node in Path("/proc").iterdir():
        if not node.name.isdecimal():
            continue
        name = read(node / "comm") or ""
        if re.search(r"^(osu!|osu-lazer|osu\.AppImage)$", name, re.I):
            match.append(int(node.name))
    return max(match) if match else None


def proc_snapshot(pid):
    if not pid:
        return {"pid": None, "status": "osu process not found; pass --pid"}
    p = Path("/proc") / str(pid)
    cgroup = read(p / "cgroup")
    scope = None
    if cgroup:
        for line in cgroup.splitlines():
            if line.startswith("0::"):
                scope = line.split("::", 1)[1]
    props = {}
    if scope and scope.startswith("/") and ".." not in scope:
        cg = Path("/sys/fs/cgroup") / scope.lstrip("/")
        for key in ("cpu.weight", "cpu.uclamp.min", "cpu.uclamp.max"):
            props[key] = read(cg / key)
    env = {}
    try:
        data = (p / "environ").read_bytes().split(b"\x00")
        for field in data:
            k, _, v = field.partition(b"=")
            key = k.decode(errors="replace")
            if key in SENSITIVE:
                env[key] = v.decode(errors="replace")
    except OSError:
        pass
    return {"pid": pid, "comm": read(p / "comm"), "cgroup": scope, "scope_props": props,
            "timerslack_ns": read(p / "timerslack_ns"), "environ": env}


def task_snapshot(pid):
    if not pid:
        return []
    result = []
    for path in sorted((Path("/proc") / str(pid) / "task").glob("[0-9]*"))[:80]:
        s = read(path / "schedstat")
        if not s:
            continue
        nums = s.split()
        if len(nums) < 3 or not all(re.fullmatch(r"\d+", x) for x in nums[:3]):
            continue
        result.append({"tid": int(path.name), "name": read(path / "comm") or "?",
                       "run_ns": int(nums[0]), "wait_ns": int(nums[1]), "slices": int(nums[2])})
    return result


def cpu_snapshot():
    out = {"temp_C": None, "throttle_count": None, "cpu_kHz": None, "governor": None, "epp": None}
    for d in Path("/sys/class/thermal").glob("thermal_zone*"):
        if read(d / "type") == "x86_pkg_temp":
            try:
                out["temp_C"] = round(int(read(d / "temp")) / 1000, 2)
            except (TypeError, ValueError):
                pass
            break
    base = Path("/sys/devices/system/cpu")
    values = {"throttle_count": base / "cpu0/thermal_throttle/package_throttle_count",
              "cpu_kHz": base / "cpufreq/policy0/scaling_cur_freq",
              "governor": base / "cpufreq/policy0/scaling_governor",
              "epp": base / "cpufreq/policy0/energy_performance_preference"}
    for key, p in values.items():
        v = read(p)
        try:
            out[key] = int(v) if key in ("throttle_count", "cpu_kHz") and v is not None else v
        except ValueError:
            pass
    return out


def display_snapshot():
    monitors = command(["hyprctl", "-j", "monitors"], parse_json=True)
    active = command(["hyprctl", "-j", "activewindow"], parse_json=True)
    if not isinstance(monitors, list):
        return {"status": "hyprctl monitors unavailable", "monitor": None, "window": None}
    mon = next((x for x in monitors if isinstance(x, dict) and x.get("name") == MONITOR), None)
    return {"status": "ok" if mon else "eDP-1 missing", "monitor": mon, "window": active if isinstance(active, dict) else None}


def alsa_snapshot():
    cards = read("/proc/asound/cards")
    pcm_index = read("/proc/asound/pcm")
    # Never claim that an arbitrary open substream is definitely the ALC257 route.
    pcms = []
    for p in sorted(Path("/proc/asound").glob("card*/pcm*p/sub*/hw_params")):
        params = read(p)
        if params and params != "closed":
            pcms.append({"path": str(p), "params": params,
                         "status": read(p.parent / "status")})
    return {"cards": cards, "pcm_index": pcm_index, "open_playback_pcms": pcms}


def pw_dump_snapshot():
    data = command(["pw-dump"], timeout=3.0, parse_json=True)
    if not isinstance(data, list):
        return {"status": "pw-dump unavailable"}
    nodes = []
    for obj in data:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        props = obj.get("info", {}).get("props") or {}
        name = str(props.get("node.name", ""))
        if "alsa_output" not in name and "osu" not in name.lower():
            continue
        keys = ("node.name", "node.description", "api.alsa.path", "api.alsa.period-size",
                "api.alsa.period-num", "api.alsa.headroom", "node.rate", "node.latency")
        nodes.append({"id": obj.get("id"), "props": {k: props.get(k) for k in keys if k in props},
                      "state": obj.get("info", {}).get("state")})
    return {"nodes": nodes}


def find_perf_logs(custom=None):
    dirs = [Path(custom).expanduser()] if custom else PATHS
    result = {}
    for root in dirs:
        for folder in (root, root / "logs", root / "Logs"):
            if not folder.is_dir():
                continue
            for name in sorted(PERF_FILES):
                p = folder / name
                try:
                    info = p.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISREG(info.st_mode):
                    result[str(p)] = info
    return result


def copy_perf_log_deltas(out, start, end):
    logdir = out / "performance-logs"
    logdir.mkdir(mode=0o700, exist_ok=True)
    results = []
    for index, (path, end_info) in enumerate(end.items()):
        p = Path(path)
        try:
            cap = 2_000_000
            offset = 0
            start_info = start.get(path)
            end_identity = (end_info.st_dev, end_info.st_ino)
            if start_info and (start_info.st_dev, start_info.st_ino) == end_identity:
                if start_info.st_size <= end_info.st_size:
                    offset = start_info.st_size
            count = end_info.st_size - offset
            if count == 0:
                continue
            with open(p, "rb", opener=lambda path, flags: os.open(path, flags | os.O_NOFOLLOW | os.O_NONBLOCK)) as source:
                info = os.fstat(source.fileno())
                if not stat.S_ISREG(info.st_mode) or (info.st_dev, info.st_ino) != end_identity:
                    raise OSError("log replaced before copy")
                source.seek(end_info.st_size - min(count, cap))
                payload = source.read(min(count, cap))
                if len(payload) != min(count, cap):
                    raise OSError("log shortened before copy finished")
            dest = logdir / p.name
            if dest.exists():
                dest = logdir / str(index) / p.name
                dest.parent.mkdir(mode=0o700)
            write_file(dest, payload, new=True)
            results.append({"source": str(p), "copied_bytes": len(payload), "truncated": count > cap,
                            "saved": str(dest.relative_to(out))})
        except OSError:
            results.append({"source": str(p), "status": "copy failed"})
    return results


def parse_slow_logs(root):
    result = {}
    folder = Path(root) / "performance-logs"
    for name in sorted(PERF_FILES):
        paths = [p for p in (folder / name, *sorted(folder.glob(f"*/{name}"))) if p.is_file()]
        if not paths:
            continue
        matches = [float(x.replace(",", "")) for p in paths
                   for x in re.findall(r"Frame length\s*:\s*(\d[\d,]*(?:\.\d+)?)\s*ms",
                                       p.read_text(errors="replace"), re.I)]
        matches = [x for x in matches if math.isfinite(x)]
        result[name] = {"slow_frame_count": len(matches), "slow_lengths_ms": dist(matches),
                        "note": "slow frames only; NOT all-frame p99"}
    return result


def parse_pw_top(path):
    """Best-effort parser for pw-top -b; raw stdout is retained for audit."""
    if not Path(path).is_file():
        return {"status": "unavailable"}
    content = re.sub(r"\x1b\[[0-9;]*m", "", Path(path).read_text(errors="replace"))
    rows = {}
    for line in content.splitlines():
        bits = line.strip().split()
        if len(bits) < 10:
            continue
        name = bits[-1]
        if "alsa_output" not in name and "osu" not in name.lower():
            continue
        # S ID QUANT RATE WAIT BUSY W/Q B/Q ERR NAME, actual columns vary.
        try:
            err = int(bits[-2])
        except ValueError:
            continue
        try:
            quantum = int(bits[2])
            rate = int(bits[3])
        except (ValueError, IndexError):
            quantum, rate = None, None
        rows.setdefault(name, []).append({"id": bits[1], "err": err, "quantum": quantum, "rate": rate})
    nodes = {}
    for name, observations in rows.items():
        first, last = observations[0], observations[-1]
        ids = {row["id"] for row in observations}
        delta = counter_delta([row["err"] for row in observations]) if len(ids) == 1 else None
        nodes[name] = {"observations": len(observations), "first_err": first["err"], "last_err": last["err"],
                       "delta_err": delta, "delta_err_source": PW_ERR_SOURCE if delta is not None else None,
                       "graph_quantum": last["quantum"], "graph_rate": last["rate"]}
    return {"nodes": nodes, "status": "parsed" if nodes else "raw_capture_only"}


def counter_delta(values):
    if len(values) >= 2 and all(a <= b for a, b in zip(values, values[1:])):
        return values[-1] - values[0]
    return None


def scanout_active(target):
    if type(target) is int and target >= 0:
        return target != 0
    if isinstance(target, str) and re.fullmatch(r"(?:0[xX])?[\da-fA-F]+", target, re.ASCII):
        return int(target, 16) != 0
    return None


def analyze_input(raw):
    devices = []
    clocks = {entry.get("path"): entry.get("clock") for entry in raw.get("status", [])
              if entry.get("status") == "opened"}
    for original in raw.get("devices", []):
        d = dict(original)
        if "timing" not in d:
            hidraw = d.get("kind") == "hidraw"
            aligned = clocks.get(d.get("path")) == MONOTONIC
            intact = aligned and d.get("syn_dropped") == 0
            d["timing"] = {"period_source": "hidraw read completion" if hidraw else "evdev SYN_REPORT",
                           "period_clock": MONOTONIC if hidraw or aligned else None,
                           "read_clock": MONOTONIC if hidraw else None,
                           "dispatch_clock": MONOTONIC if aligned else None}
            d["read_interval_ms"] = d["period_ms"] if hidraw else dist([])
            d["counts_complete"] = None
            if hidraw:
                d["reads"] = d["reports"]
            if not intact:
                d["observer_delay_ms"] = dist([])
            # Old aggregates cannot isolate intervals that were zero or crossed a drop.
            if not hidraw and (not intact or d["period_ms"]["min"] == 0):
                d["period_ms"] = dist([])
                d["histogram"] = histogram([], 0, 12, 0.5)
        devices.append(d)
    return {**raw, "devices": devices}


def analyze_pw_top(raw):
    if not raw or "nodes" not in raw:
        return raw
    # Endpoints alone cannot identify a reset or a replacement under the same node name.
    nodes = {name: {**row, "delta_err": row.get("delta_err") if row.get("delta_err_source") == PW_ERR_SOURCE else None}
             for name, row in raw["nodes"].items()}
    return {**raw, "nodes": nodes}


def analyze(data):
    samples = data.get("samples", [])
    temps = [x["cpu"]["temp_C"] for x in samples if isinstance(x.get("cpu", {}).get("temp_C"), (int, float))]
    throttles = [x["cpu"]["throttle_count"] for x in samples if type(x.get("cpu", {}).get("throttle_count")) is int]
    eligible, dso_observed, dso, tearing_observed, torn = 0, 0, 0, 0, 0
    dso_blockers, tearing_blockers = Counter(), Counter()
    for item in samples:
        disp = item.get("display") or {}
        win, mon = disp.get("window") or {}, disp.get("monitor") or {}
        if (disp.get("status", "ok") != "ok" or win.get("class") not in ("osu!", "osu-lazer")
                or win.get("fullscreen") != 2 or type(win.get("fullscreenClient")) is not int
                or win["fullscreenClient"] != 0 or mon.get("name") != MONITOR):
            continue
        if None not in (win.get("monitor"), mon.get("id")) and win["monitor"] != mon["id"]:
            continue
        eligible += 1
        active_dso = scanout_active(mon.get("directScanoutTo"))
        tearing = mon.get("activelyTearing")
        if active_dso is not None:
            dso_observed += 1
        if active_dso is True:
            dso += 1
            if isinstance(tearing, bool):
                tearing_observed += 1
                torn += tearing
        elif active_dso is False:
            for reason in mon.get("directScanoutBlockedBy") or []:
                dso_blockers[str(reason)] += 1
        if tearing is False:
            for reason in mon.get("tearingBlockedBy") or []:
                tearing_blockers[str(reason)] += 1
    tasks = {}
    for item in samples:
        for th in item.get("threads", []):
            tasks.setdefault((th["tid"], th["name"]), []).append(th)
    threads = []
    for (tid, name), rows in tasks.items():
        waits, runs, slices = (counter_delta([row[key] for row in rows]) for key in ("wait_ns", "run_ns", "slices"))
        if None not in (waits, runs, slices):
            threads.append({"tid": tid, "name": name, "run_ms": round(runs / 1e6, 3),
                            "runqueue_wait_ms": round(waits / 1e6, 3), "slices": slices, "observations": len(rows),
                            "wait_per_slice_ms": round(waits / 1e6 / slices, 4) if slices else None,
                            "note": "runqueue wait / scheduling slices (not event-to-Update latency)"})
    threads.sort(key=lambda x: x["runqueue_wait_ms"], reverse=True)
    return {"capture": data.get("capture", {"status": "unknown"}),
            "input": analyze_input(data.get("input", {})), "audio": {"alsa_start": data.get("alsa_start"),
                                            "alsa_end": data.get("alsa_end"),
                                            "pw_start": data.get("pw_start"),
                                            "pw_end": data.get("pw_end"),
                                            "pw_top": analyze_pw_top(data.get("pw_top"))},
            "update": {"thread_sched": threads, "game_log": data.get("game_log", {}),
                       "note": "No per-frame Update latency histogram from procfs; only kernel scheduler aggregates and slow-frame logs."},
            "draw": {"eligible_samples": eligible, "dso_observed_samples": dso_observed, "dso_samples": dso,
                     "tearing_observed_dso_samples": tearing_observed, "actively_tearing_samples": torn,
                     "dso_blockers": dict(dso_blockers),
                     "tearing_blockers": dict(tearing_blockers),
                     "dso_ratio": round(dso / dso_observed * 100, 1) if dso_observed else None,
                     "tearing_ratio_among_dso": round(torn / tearing_observed * 100, 1) if tearing_observed else None,
                     "note": "Hyprland sampled state, not actual async KMS-flip success or optical latency."},
            "system": {"temp_C": dist(temps), "throttle_delta": counter_delta(throttles), "throttle_observations": len(throttles),
                       "cpu_kHz": dist([x["cpu"]["cpu_kHz"] for x in samples if isinstance(x.get("cpu", {}).get("cpu_kHz"), int)]),
                       "samples": len(samples), "proc": data.get("proc_start")}}


def pill(val, default="未測定"):
    return str(val) if val is not None else default


def fmt(num, digits=2):
    return f"{num:.{digits}f}" if isinstance(num, (int, float)) else "未測定"


def esc(x):
    return html.escape(str(x))


def metric(name, value, note, state="observed"):
    v = esc(value)
    return f'<div class="metric"><div class="mname">{esc(name)}</div><div class="mvalue">{v}</div><div class="micro">{esc(note)}</div><span class="kind {state}">{state}</span></div>'


def svg_hist(h):
    if not h or not h.get("counts") or sum(h["counts"]) == 0:
        return '<div class="muted">分布データなし</div>'
    counts = h["counts"]
    maxv = max(counts)
    w, step = 720, 720 / len(counts)
    out = [f'<svg viewBox="0 0 760 170" role="img" aria-label="入力レポート間隔ヒストグラム">']
    for i, value in enumerate(counts):
        height = round(value / maxv * 123, 2)
        out.append(f'<rect x="{i*step+5:.1f}" y="{140-height:.1f}" width="{max(1,step-2):.1f}" height="{height:.1f}" fill="#5aa9b3"><title>{i*h["step"]:.1f}–{(i+1)*h["step"]:.1f}ms: {value}</title></rect>')
    for ms in (0, 2.5, 5, 7.5, 10, 12):
        x = 5 + ms / (len(counts) * h["step"]) * 720
        out.append(f'<text x="{x:.1f}" y="161" fill="#9aacb9" font-size="11">{ms:g}ms</text>')
    out.append('</svg>')
    return ''.join(out)


def svg_temps(samples):
    temps = [(i, x.get("cpu", {}).get("temp_C")) for i, x in enumerate(samples)]
    temps = [(i, t) for i, t in temps if isinstance(t, (int, float))]
    if len(temps) < 2:
        return '<div class="muted">温度データなし</div>'
    mi, ma = min(t for _, t in temps), max(t for _, t in temps)
    pad = max(2, (ma-mi)*.15)
    lo, hi = mi-pad, ma+pad
    xmax = max(i for i, _ in temps)
    points = ' '.join(f'{30+690*i/max(1,xmax):.2f},{150-112*(t-lo)/(hi-lo):.2f}' for i,t in temps)
    return f'<svg viewBox="0 0 760 170" role="img" aria-label="CPU温度の時系列"><text x="3" y="20" fill="#9aacb9" font-size="12">{ma:.1f}°C</text><text x="3" y="150" fill="#9aacb9" font-size="12">{mi:.1f}°C</text><polyline points="{points}" fill="none" stroke="#efb76b" stroke-width="2.8"/></svg>'


def simple_table(headers, rows):
    out = ['<table><thead><tr>']
    out += [f'<th>{esc(x)}</th>' for x in headers]
    out += ['</tr></thead><tbody>']
    for row in rows:
        out.append('<tr>' + ''.join(f'<td>{esc(item)}</td>' for item in row) + '</tr>')
    return ''.join(out + ['</tbody></table>'])


def html_report(data, summary):
    input_summary = summary["input"]
    devices = input_summary.get("devices", [])
    main_table = []
    read_table = []
    hist = []
    for d in devices:
        vals, timing = d["period_ms"], d["timing"]
        reads, dispatch = d["read_interval_ms"], d["observer_delay_ms"]
        completeness = {True: "記録区間内の完了フレーム", False: "不完全", None: "不明"}[d["counts_complete"]]
        counters = ("—", "—", "—") if d["kind"] == "hidraw" else (d["syn_dropped"], d["key_down"], d["key_up"])
        main_table.append((d["path"], timing["period_source"], pill(timing["period_clock"]), d["reports"],
                           vals["count"], fmt(vals["p50"], 3), fmt(vals["p95"], 3),
                           fmt(vals["p99"], 3), fmt(vals["p99_9"], 3), *counters, completeness))
        read_table.append((d["path"], pill(timing["read_clock"]), pill(d.get("reads")),
                           reads["count"], fmt(reads["p50"], 3), fmt(reads["p95"], 3), fmt(reads["p99"], 3),
                           pill(timing["dispatch_clock"]), dispatch["count"], fmt(dispatch["p50"], 3),
                           fmt(dispatch["p95"], 3), fmt(dispatch["p99"], 3)))
        hist.append(f'<h3>{esc(d["name"] or d["path"])} — {esc(d["kind"])}</h3>{svg_hist(d["histogram"])}'
                    f'<p class="micro">区間外 {d["histogram"]["outside_range"]}件。停止/静止による長い間隔は欠落とは判定しません。</p>')
    if not devices:
        hist.append('<p class="muted">対象デバイスは開けませんでした。権限・識別子を確認してください。</p>')
    sysd = summary["system"]
    dra = summary["draw"]
    proc = sysd.get("proc") or {}
    env = proc.get("environ") or {}
    sleep = summary["update"].get("game_log") or {}
    rows = [(name, val.get("slow_frame_count"), fmt(val.get("slow_lengths_ms", {}).get("max"), 1)) for name,val in sleep.items()]
    rows_sched = [(x["tid"], x["name"], x["observations"], fmt(x["run_ms"]), fmt(x["runqueue_wait_ms"]),
                   x["slices"], fmt(x["wait_per_slice_ms"], 4))
                  for x in summary["update"]["thread_sched"][:20]]
    alsa = summary["audio"].get("alsa_end") or {}
    pcm_rows = [(x["path"], x["params"].replace('\n', '; ')) for x in alsa.get("open_playback_pcms", [])]
    pw = summary["audio"].get("pw_top") or {}
    pwrows = [(k, v["observations"], pill(v.get("graph_quantum")), pill(v.get("graph_rate")),
               pill(v.get("first_err")), pill(v.get("last_err")), pill(v["delta_err"])) for k, v in pw.get("nodes", {}).items()]
    nodeprops = (summary["audio"].get("pw_end") or {}).get("nodes", [])
    prop_rows = [(x.get("id"), x.get("props", {}).get("node.name"), x.get("props", {}).get("api.alsa.period-size"),
                  x.get("props", {}).get("api.alsa.period-num"), x.get("props", {}).get("api.alsa.headroom")) for x in nodeprops]
    warnings = ["生ログには端末名、スレッド名、アプリ情報が含まれます。公開前に確認してください。",
                "単独の短時間計測では優劣を判定できません。8x/Unlimited、BASS -128/-256は同条件の別runで比較してください。",
                "Input→Updateイベント別待機時間、BASS実効内部周期、音の物理的開始、DRM Flip時刻、光学的Input-to-photonは本キットでは未測定です。"]
    config = data.get('config', {})
    outcome = summary["capture"]
    title = f'osu! latency lab | {config.get("label", "untitled")}'
    style = '''
:root{color-scheme:dark;font-family:ui-sans-serif,system-ui,sans-serif;background:#0e1520;color:#e7edf3}
body{max-width:1170px;margin:auto;padding:24px 24px 75px;line-height:1.65}header{border-bottom:1px solid #334155;padding:20px 0 28px}h1{letter-spacing:-.03em;font-size:2rem}h2{margin-top:0;font-size:1.25rem}h3{font-size:1rem;color:#bdd4e5}.intro,.muted,.micro{color:#a5b4c3}.micro{font-size:.79rem}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(225px,1fr));gap:14px}.metric{background:#182333;border:1px solid #334457;padding:17px;border-radius:12px;min-height:130px;display:flex;flex-direction:column}.mname{color:#aabacf;font-size:.85rem}.mvalue{font-size:1.8rem;font-weight:700;font-variant-numeric:tabular-nums}.kind{font:600 .66rem system-ui;color:#8dc8d4;margin-top:auto;letter-spacing:.03em;text-transform:uppercase}.kind.proxy{color:#eed09b}.kind.unknown{color:#d1a7a7}section{margin-top:22px;border:1px solid #304156;border-radius:15px;padding:22px;background:#111d2a}.tabwrap{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:.85rem}th,td{padding:10px 12px;border-bottom:1px solid #304156;text-align:left;vertical-align:top}th{color:#95b3c4}svg{max-width:100%;height:auto}.warning{border-left:3px solid #c9a66b;padding:9px 14px;margin:10px 0;background:#202533}.tag{font-size:.74rem;color:#86c6d1;border:1px solid #447781;border-radius:5px;padding:3px 7px;margin-right:8px}code{color:#b9dbdf}ul{padding-left:20px}details{margin-top:8px}a{color:#92d6e7}'''
    body = [f'<header><span class="tag">MEASUREMENT / not a latency proof</span><span class="tag">{esc(config.get("label"))}</span><h1>{esc(title)}</h1>'
            f'<p class="intro">{esc(data.get("started"))}〜{esc(data.get("ended"))} ／ '
            f'capture {esc(outcome["status"])} ／ 要求 {esc(pill(config.get("seconds")))} s ／ '
            f'{esc(pill(outcome.get("clock")))} 観測時間 {fmt(outcome.get("elapsed_s"), 3)} s ／ '
            f'公式osu!無改変・root権限不要・Inputは読み取りのみ</p></header>']
    if outcome.get("signal") or outcome.get("failures"):
        body.append('<div class="warning">' + esc(json.dumps(outcome, ensure_ascii=False)) + '</div>')
    dso_coverage = f'{dra["dso_samples"]}/{dra["dso_observed_samples"]} observed ／ {dra["eligible_samples"]} eligible'
    tear_coverage = f'{dra["actively_tearing_samples"]}/{dra["tearing_observed_dso_samples"]} observed ／ {dra["dso_samples"]} DSO'
    body.append('<section><h2>結論の見取り図</h2><div class="grid">')
    body += [metric('Input: 接続済デバイス',f'{len(devices)} 台','hidrawとevdevを区別 / 実入力待ち時間は未知'),
             metric('Audio: BASS要求値', pill(env.get('OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD')),
                    'プロセス環境変数。実効内部periodではありません', 'proxy'),
             metric('Update: ゲームスレッド',pill(len(summary['update']['thread_sched']) if proc.get('pid') else None),'proc schedstat / 個別Update周期のp99ではありません','proxy'),
             metric('Draw: 既知条件でのDSO',fmt(dra['dso_ratio'],1)+'%' if dra['dso_ratio'] is not None else '未測定',
                    dso_coverage, 'observed' if dra['dso_ratio'] is not None else 'unknown'),
             metric('Draw: tearing状態',fmt(dra['tearing_ratio_among_dso'],1)+'%' if dra['tearing_ratio_among_dso'] is not None else '未測定',
                    tear_coverage, 'observed' if dra['tearing_ratio_among_dso'] is not None else 'unknown'),
             metric('CPU最大温度',fmt(sysd['temp_C']['max'])+'°C' if sysd['temp_C']['max'] is not None else '未測定',
                    f'sysfs {sysd["temp_C"]["count"]}/{sysd["samples"]} samples',
                    'observed' if sysd['temp_C']['count'] else 'unknown')]
    body.append('</div></section>')
    body.append('<section><h2>Input <span class="kind">device intervals</span></h2>')
    body.append(f'<p class="intro">CTL-472の申告設定 {esc(pill(config.get("expected_tablet_hz")))} Hz。'
                'hidraw間隔はユーザー空間の読み出し完了時刻、evdev間隔は整列済みカーネルのSYN_REPORT時刻。'
                'evdevは状態変化を記録し、欠落をまたぐ区間を除外します。静止時の空白だけでは欠落を判定できません。</p>')
    body.append('<div class="tabwrap">'+simple_table(['デバイス','間隔の由来','時計','報告数','間隔数','p50 ms','p95 ms','p99 ms',
                'p99.9 ms','SYN_DROPPED','press','release','カウントの完全性'],main_table)+'</div>')
    body+=hist
    body.append('<h3>読み出し完了間隔とevdev取得遅延</h3><p class="micro">成功したreadごとに時刻を記録。'
                '取得遅延は整列済みSYN_REPORTから読み出し完了までの差（0以上5秒未満）。</p><div class="tabwrap">'+
                simple_table(['デバイス','read時計','read数','間隔数','read p50 ms','read p95 ms','read p99 ms',
                              '取得遅延の時計','報告数','遅延 p50 ms','遅延 p95 ms','遅延 p99 ms'],read_table)+'</div>')
    body.append('<details><summary>デバイスのアクセス状態</summary><pre>'+esc(json.dumps(input_summary.get('status'),ensure_ascii=False,indent=2))+'</pre></details></section>')
    body.append('<section><h2>Audio <span class="kind proxy">driver/proxy</span></h2>')
    body.append(f'<p class="intro">比較ラベルのBASS要求値 {esc(pill(config.get("expected_bass")))}。'
                '実効ALSA hw_paramsはPCMが開いている場合に限り取得。PipeWire ERRはXRunとその他のエラーの合計です。</p>')
    body.append('<h3>開いているALSA playback PCM</h3><div class="tabwrap">'+simple_table(['PCM','hw_params'],pcm_rows)+'</div>')
    body.append('<h3>PipeWireノードの要求値</h3><div class="tabwrap">'+simple_table(['ID','ノード','period-size','period-num','headroom'],prop_rows)+'</div>')
    body.append('<h3>pw-top Graph / ERR</h3><p class="micro">'+esc(pill(pw.get('status')))+'</p><div class="tabwrap">'+
                simple_table(['Node','観測行数','QUANT frames','RATE Hz','最初のERR','最後のERR','ERR増分'],pwrows)+
                '</div><p class="micro">QUANT/RATEはPipeWire graph/streamの観測値。ERR増分には同一ノードIDで減少しないERR観測の記録が必要です。</p></section>')
    body.append('<section><h2>Update <span class="kind proxy">scheduler/slow-frame</span></h2>')
    body.append('<p class="intro">procfsのschedstatで累積runqueue待機時間を記録します。Updateフレーム周期分布は別物です。Ctrl+F2のperformanceログは遅延フレームの選択的ログであり、全フレームp99は算出しません。</p>')
    body.append(f'<p class="micro">PID {esc(proc.get("pid"))} / cgroup {esc(proc.get("cgroup"))} / timerslack {esc(proc.get("timerslack_ns"))}ns / '
                f'cpu.weight {esc(proc.get("scope_props",{}).get("cpu.weight"))} / cpu.uclamp.min {esc(proc.get("scope_props",{}).get("cpu.uclamp.min"))}</p>')
    body.append('<div class="tabwrap">'+simple_table(['TID','name','観測数','CPU run ms','runqueue wait ms','slices','wait/slice ms'],rows_sched)+'</div>')
    log_capture = data.get("log_capture", [])
    body.append(f'<p class="micro">保存ログ {sum("saved" in row for row in log_capture)}件 ／ '
                f'上限で切り詰め {sum(row.get("truncated", False) for row in log_capture)}件 ／ '
                f'コピー失敗 {sum(row.get("status") == "copy failed" for row in log_capture)}件</p>')
    body.append('<h3>osu!公式performanceログのslow frame</h3><div class="tabwrap">'+simple_table(['ログ','slow frame数','最大 ms'],rows)+'</div></section>')
    body.append('<section><h2>Draw <span class="kind">DSO state</span></h2>')
    body.append('<p class="intro">対象はeDP-1で前面のosu!がfullscreen 2/0の点サンプル。'
                'DSO率はdirectScanoutToを取得した対象サンプル、tearing率はactivelyTearingを取得したDSOサンプルから算出。'
                'i915の実flip時刻、描画フレーム時間、光学遅延は未測定です。</p>')
    body.append(f'<p class="micro">Hyprland samples {sysd["samples"]} ／ 要求間隔 {fmt(outcome.get("sample_interval_s"), 1)} s</p>')
    body.append('<h3>DSOが阻害された理由（既知2/0条件内）</h3>'+simple_table(['reason','samples'],list(dra.get('dso_blockers',{}).items())))
    body.append('<h3>Tearingが阻害された理由（既知2/0条件内）</h3>'+simple_table(['reason','samples'],list(dra.get('tearing_blockers',{}).items()))+'</section>')
    body.append('<section><h2>熱・P-state</h2>'+svg_temps(data.get('samples',[]))+
                f'<p class="micro">グラフ横軸はサンプル順。sysfs温度p95 {fmt(sysd["temp_C"]["p95"])} °C（{sysd["temp_C"]["count"]}件） ／ '
                f'throttle増分 {pill(sysd["throttle_delta"])}（{sysd["throttle_observations"]}件） ／ '
                f'CPU周波数p50 {fmt(sysd["cpu_kHz"]["p50"],0)} kHz（{sysd["cpu_kHz"]["count"]}件）</p></section>')
    body.append('<section><h2>測定の限界と次の比較</h2>')
    for message in warnings:
        body.append('<div class="warning">'+esc(message)+'</div>')
    body.append('<p class="intro">比較は同一譜面・同じプレイ時間・同じペン操作・同一のDiscord/配信条件で実施。まず400Hz/-128/8x/同期提示をベースラインとして記録し、1条件ずつ変えます。結果は <code>osu-lab compare sessionA sessionB</code> で重ねて表示します。</p></section>')
    return '<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+esc(title)+'</title><style>'+style+'</style><body>'+''.join(body)+'</body></html>'


def positive_number(value):
    return type(value) in (int, float) and 0 < value < math.inf


def recorded_text(value):
    return isinstance(value, str) and bool(value.strip())


def observed_display_mode(mode):
    width, height, refresh, vrr = mode
    return all(positive_number(value) for value in (width, height, refresh)) and type(vrr) is bool


def comparable(entries):
    # Recorded metadata can rule out matching conditions, but cannot verify play/workload.
    for key, observed in (("seconds", positive_number), ("expected_tablet_hz", positive_number),
                          ("expected_bass", recorded_text), ("game_settings", recorded_text)):
        first, second = (e["config"].get(key) for e in entries)
        if not observed(first) or not observed(second) or first != second:
            return False
    first, second = (e.get("version") for e in entries)
    if not recorded_text(first) or first != second:
        return False
    environments = [e.get("environment") or {} for e in entries]
    for env in environments:
        modes = env.get("monitor_modes")
        if not recorded_text(env.get("bass")) or not modes or not all(observed_display_mode(mode) for mode in modes):
            return False
    if environments[0] != environments[1]:
        return False
    windows = [e["analysis"].get("capture", {}) for e in entries]
    if any(w.get("status") != "complete" or w.get("clock") != MONOTONIC for w in windows):
        return False
    first_interval, second_interval = (w.get("sample_interval_s") for w in windows)
    elapsed = [w.get("elapsed_s") for w in windows]
    return (positive_number(first_interval) and positive_number(second_interval) and first_interval == second_interval
            and all(positive_number(value) for value in elapsed) and abs(elapsed[0] - elapsed[1]) <= first_interval)


def comparison_values(summary):
    draw, system = summary["draw"], summary["system"]
    update = next((t for t in summary["update"]["thread_sched"] if re.search("update", t["name"], re.I)), {})
    hidraw = next((d["period_ms"] for d in summary["input"]["devices"] if d["kind"] == "hidraw"), dist([]))
    pw = summary["audio"].get("pw_top") or {}
    alsa = [r for k, r in pw.get("nodes", {}).items() if "alsa_output" in k]
    errors = [r["delta_err"] for r in alsa if r["delta_err"] is not None]
    return [
        (hidraw["p50"], f'{hidraw["count"]} intervals'),
        (sum(errors) if alsa and len(alsa) == len(errors) else None, f'{len(errors)}/{len(alsa)} nodes'),
        (update.get("wait_per_slice_ms"), f'{pill(update.get("slices"))} slices'),
        (draw["dso_ratio"], f'{draw.get("dso_samples", 0)}/{draw.get("dso_observed_samples", 0)} observed'),
        (draw["tearing_ratio_among_dso"],
         f'{draw.get("actively_tearing_samples", 0)}/{draw.get("tearing_observed_dso_samples", 0)} observed DSO'),
        (system["temp_C"]["max"], f'{system["temp_C"].get("count", 0)} samples'),
        (system["throttle_delta"], f'{system.get("throttle_observations", 0)} samples'),
    ]


def comparison_html(entries):
    labels = [x["config"].get("label", "untitled") for x in entries]
    pair = len(entries) == 2
    show_delta = pair and comparable(entries)
    metrics = [
        ("Input: hidraw中央値（ms）", "CLOCK_MONOTONICによるread完了間隔"),
        ("Audio: ALSA ERR増分", "pw-topのALSA出力ノード。XRun以外のエラーを含む"),
        ("Update: runqueue wait/slice（ms）", "procfs schedstatの代理指標"),
        ("Draw: DSO率（%）", "Hyprlandの対象サンプルのうち、DSOを観測できた件数が母数"),
        ("Draw: tearing状態率（%）", "HyprlandのDSOサンプルのうち、tearingを観測できた件数が母数"),
        ("CPU最高温度（°C）", "sysfsの点サンプル"),
        ("スロットリング増分", "sysfs package counterの観測差"),
    ]
    observations = [comparison_values(e["analysis"]) for e in entries]
    rows = []
    for (title, note), measured in zip(metrics, zip(*observations)):
        columns = [f"{fmt(value, 3)} ({coverage})" for value, coverage in measured]
        if pair:
            left, right = (value for value, _ in measured)
            columns.append(f"{right - left:+.3f}" if show_delta and None not in (left, right) else "未判定")
        rows.append((title, *columns, note))
    conditions = []
    for cfg, summary, env in ((e["config"], e["analysis"], e.get("environment") or {}) for e in entries):
        window = summary.get("capture", {})
        draw = summary["draw"]
        modes = ", ".join(f"{width}×{height} @ {rate} Hz (VRR {'on' if vrr else 'off'})"
                          for width, height, rate, vrr in (env.get("monitor_modes") or [])
                          if observed_display_mode((width, height, rate, vrr)))
        bass = env.get("bass")
        conditions.append((cfg.get("label"), window.get("status", "unknown"),
                           pill(cfg.get("seconds")), fmt(window.get("elapsed_s"), 3),
                           pill(cfg.get("expected_tablet_hz")), pill(cfg.get("expected_bass")),
                           pill(bass if recorded_text(bass) else None),
                           pill(cfg.get("game_settings")), modes or "未測定",
                           draw.get("eligible_samples", 0)))
    body = '<header><h1>osu! latency lab · comparison</h1><p class="intro">記録された観測値をセッションごとに表示します。</p></header>'
    body += '<section><h2>計測条件</h2><div class="tabwrap">' + simple_table(
        ['セッション', 'capture', '要求 s', '経過 s', '申告 tablet Hz', 'BASSラベル', 'BASS環境変数', 'ゲーム設定ラベル',
         'eDP-1表示モード', '2/0対象件数'], conditions) + '</div></section>'
    if pair and not show_delta:
        body += '<p>記録条件が異なるか不明、または計測区間が不完全なため、Δは未判定。</p>'
    cols = ['指標', *labels] + (['Δ（右−左）'] if pair else []) + ['由来']
    body += '<section><h2>観測値</h2><div class="tabwrap">' + simple_table(cols, rows) + '</div></section>'
    body += '<p>比較には同じ譜面、操作、周辺アプリと計測方法での反復が必要です。物理的な入力・発音・発光の遅延は未測定です。</p>'
    return '<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:15px/1.7 system-ui;color:#e9eff5;background:#101925;max-width:1150px;margin:auto;padding:24px}.intro{color:#99b2c9}section{background:#162333;border:1px solid #405064;border-radius:12px;padding:20px;margin-top:20px}.tabwrap{overflow:auto}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #314457;padding:11px;text-align:left}th{color:#9ad4df}</style><body>'+body+'</body></html>'


def terminate(signum, _frame):
    global STOP
    if STOP is None:
        STOP = signum


@contextmanager
def capture_signals():
    global STOP
    STOP = None
    previous = {}
    try:
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous[sig] = signal.signal(sig, terminate)
        yield
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


@contextmanager
def pw_top_capture(out, seconds, status):
    if STOP is not None or not shutil.which("pw-top"):
        status["status"] = "unavailable"
        yield
        return
    try:
        stream = open(out / "pw-top-batch.txt", "xb", opener=lambda path, flags: os.open(path, flags, 0o600))
    except OSError:
        status["status"] = "output unavailable"
        yield
        return
    with stream:
        try:
            process = subprocess.Popen(["pw-top", "-b", "-n", str(seconds + 3)],
                                       stdout=stream, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            status["status"] = "launch failed"
            yield
            return
        try:
            yield
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
                    status["status"] = "forced stop"
            elif process.returncode != 0:
                status["status"] = "exited early"
            status["returncode"] = process.returncode


def capture_window(args, out, data, outcome, pw_status):
    if STOP is not None:
        return
    observer = InputObserver(args.hidraw, args.event)
    try:
        with pw_top_capture(out, args.seconds, pw_status):
            if STOP is not None:
                return
            start = time.monotonic()
            next_tick = start
            end = start + args.seconds
            try:
                while STOP is None and (now := time.monotonic()) < end:
                    if now >= next_tick:
                        data["samples"].append({"elapsed_s": round(now - start, 3),
                                                "display": display_snapshot(), "cpu": cpu_snapshot(),
                                                "threads": task_snapshot(data["proc_start"]["pid"])})
                        next_tick += 1.0
                        if next_tick < now:
                            next_tick = now + 1.0
                    if STOP is None:
                        observer.sample(max(0, min(0.05, next_tick - time.monotonic(), end - time.monotonic())))
            except Exception as e:
                note_failure(outcome, "sampling", e)
            finally:
                outcome["elapsed_s"] = round(time.monotonic() - start, 3)
    finally:
        observer.close()
        data["input"] = observer.result()


def note_failure(outcome, stage, error):
    outcome["failures"].append({"stage": stage, "type": type(error).__name__})
    print(f"osu-lab: {stage}: {error}", file=sys.stderr)


def collect_capture(args, out):
    outcome = {"clock": MONOTONIC, "elapsed_s": 0.0, "sample_interval_s": 1.0, "failures": []}
    data = {"version": VERSION, "started": stamp(), "capture": outcome,
            "config": {"label": args.label, "seconds": args.seconds, "expected_tablet_hz": args.tablet_hz,
                       "game_settings": args.game_settings, "expected_bass": args.bass,
                       "note": args.note}, "samples": []}
    start_log = None
    pw_status = {}
    try:
        if STOP is None:
            start_log = find_perf_logs(args.logs)
            data["proc_start"] = proc_snapshot(proc_pid(args.pid))
            data["alsa_start"] = alsa_snapshot()
        if STOP is None:
            data["pw_start"] = pw_dump_snapshot()
    except Exception as e:
        note_failure(outcome, "setup", e)
    else:
        capture_window(args, out, data, outcome, pw_status)
    data["ended"] = stamp()
    try:
        if STOP is None:
            data["alsa_end"] = alsa_snapshot()
        if STOP is None:
            data["pw_end"] = pw_dump_snapshot()
        data["pw_top"] = {**parse_pw_top(out / "pw-top-batch.txt"), **pw_status}
        if start_log is not None:
            data["log_capture"] = copy_perf_log_deltas(out, start_log, find_perf_logs(args.logs))
            data["game_log"] = parse_slow_logs(out)
    except Exception as e:
        note_failure(outcome, "finalization", e)
    received = STOP
    outcome["signal"] = signal.Signals(received).name if received is not None else None
    outcome["status"] = "partial" if received is not None or outcome["failures"] else "complete"
    return data


def render_report(root, data):
    summary = analyze(data)
    report_html = html_report(data, summary)
    write_json(root / "analysis.json", summary)
    write_file(root / "report.html", report_html)


def capture(args):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,60}", args.label):
        raise SystemExit("label must be 1..61 safe ASCII letters/digits/._-")
    if args.seconds < 10 or args.seconds > 600:
        raise SystemExit("--seconds must be 10..600")
    root = Path(args.out).expanduser().resolve()
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    # A fresh private session leaves the surrounding directory's permissions intact.
    out = root / f"{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}-{args.label}"
    with capture_signals():
        out.mkdir(mode=0o700)
        marker = out / INCOMPLETE
        write_file(marker, "Capture in progress or stopped before data.json was published.\n", new=True)
        print(f"osu-lab capture → {out}\n"
              f"Keep osu! foreground for {args.seconds}s; input is passive read-only.\n"
              f"Expected CTL-472 setting: {args.tablet_hz}Hz (metadata, not assumed measured).", file=sys.stderr, flush=True)
        data = collect_capture(args, out)
        write_json(out / "data.json", data, new=True)
        marker.unlink()
        render_report(out, data)
        print(f"Capture {data['capture']['status']}: {len(data['samples'])} system samples; "
              f"report: {out/'report.html'}\n"
              f"Private raw evidence: {out/'data.json'}", file=sys.stderr)
    return 128 + STOP if STOP is not None else int(data["capture"]["status"] != "complete")


def load_capture(root):
    path = root / "data.json"
    if (root / INCOMPLETE).exists() and not path.is_file():
        raise ValueError(f"incomplete capture: {root}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(data, dict) or not isinstance(data.get("config"), dict)
            or not isinstance(data.get("samples"), list) or not all(isinstance(x, dict) for x in data["samples"])):
        raise ValueError(f"invalid capture schema: {path}")
    return data


def report(args):
    root = Path(args.session).expanduser()
    render_report(root, load_capture(root))
    print(root / "report.html")
    return 0


def compare(args):
    entries = []
    for folder in args.sessions:
        data = load_capture(Path(folder).expanduser().resolve())
        proc = data.get("proc_start") or {}
        monitors = set()
        for sample in data["samples"]:
            display = sample.get("display") or {}
            mon = display.get("monitor") or {}
            if display.get("status", "ok") == "ok" and mon.get("name") == MONITOR:
                monitors.add(tuple(mon.get(key) for key in ("width", "height", "refreshRate", "vrr")))
        environment = {"bass": (proc.get("environ") or {}).get("OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD"),
                       "monitor_modes": sorted(monitors, key=repr)}
        entries.append({"config": data["config"], "analysis": analyze(data), "version": data.get("version"),
                        "environment": environment})
    root = Path(args.out).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    dest = root / "comparison.html"
    write_file(dest, comparison_html(entries))
    write_json(root / "comparison.json", entries)
    print(dest)
    return 0


def main():
    p = argparse.ArgumentParser(description="osu! latency lab (read-only; no input injection or binary modification)")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("devices", help="Identify candidate CTL-472/Sayo interfaces (without reading events)")
    c = sub.add_parser("capture", help="Capture all four domains and produce a standalone HTML report")
    c.add_argument("--label", required=True)
    c.add_argument("--seconds", type=int, default=90)
    c.add_argument("--out", default=str(Path.home() / "osu-lab-results"))
    c.add_argument("--pid", type=int)
    c.add_argument("--hidraw", action="append", default=[], help="explicit tablet interface /dev/hidrawN")
    c.add_argument("--event", action="append", default=[], help="explicit evdev interface /dev/input/eventN")
    c.add_argument("--logs", help="custom path containing osu performance-*.log files")
    c.add_argument("--tablet-hz", type=int, default=400, choices=(125, 200, 250, 333, 400, 500, 1000))
    c.add_argument("--game-settings", default="8x-sync", help="experimental condition label only")
    c.add_argument("--bass", default="-128", choices=("-128", "-256"), help="expected setting label only")
    c.add_argument("--note", default="")
    r = sub.add_parser("report", help="Rebuild report from saved JSON")
    r.add_argument("session")
    b = sub.add_parser("compare", help="Compare two or more independent captures")
    b.add_argument("sessions", nargs="+", help="session directory paths")
    b.add_argument("--out", default=str(Path.home() / "osu-lab-results" / Path("comparison")))
    args = p.parse_args()
    if args.command == "devices":
        print(json.dumps(node_candidates(),ensure_ascii=False,indent=2))
        return 0
    if args.command == "capture":
        return capture(args)
    if args.command == "report":
        return report(args)
    if args.command == "compare":
        if len(args.sessions) < 2:
            p.error("compare requires at least two sessions")
        return compare(args)
    return 64


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, json.JSONDecodeError) as e:
        print(f"osu-lab: {e}", file=sys.stderr)
        raise SystemExit(1)
