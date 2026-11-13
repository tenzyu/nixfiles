#!/usr/bin/env python3
"""Read-only Linux/Hyprland/PipeWire osu! telemetry. No game/firmware modifications.

The output deliberately distinguishes measured, proxy and unobservable quantities.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import glob
import html
import json
import math
import os
import re
import selectors
import shutil
import signal
import statistics
import struct
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

VERSION = "2026-11-13.1"
EVENT = struct.Struct("@llHHi")  # struct input_event on native 64-bit Linux
EVIOCSCLOCKID = 0x400445A0  # _IOW('E', 0xA0, int), CLOCK_MONOTONIC=1
MONITOR = "eDP-1"
PATHS = [Path.home() / ".local/share/osu", Path.home() / ".local/share/osu-lazer", Path.home() / ".config/osu"]
PERF_FILES = {"performance-input.log", "performance-update.log", "performance-draw.log", "performance-audio.log"}
SENSITIVE = {"OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD", "SDL_VIDEODRIVER", "PIPEWIRE_LATENCY"}
STOP = False


def stamp():
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def write_json(path, data):
    path = Path(path)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


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
        self.selector = selectors.DefaultSelector()
        devs = node_candidates()
        for kind, overrides in (("hidraw", override_hidraw or []), ("evdev", override_event or [])):
            for device in overrides:
                if not re.fullmatch(r"/dev/hidraw\d+" if kind == "hidraw" else r"/dev/input/event\d+", device):
                    raise ValueError(f"unsafe device path: {device}")
                if not any(d["path"] == device for d in devs):
                    devs.append({"kind": kind, "path": device, "name": "manual selection", "auto": False})
        self.devices = []
        self.status = []
        for d in devs:
            record = {**d, "reports": 0, "key_down": 0, "key_up": 0, "key_repeat": 0,
                      "pen_touch_down": 0, "pen_touch_up": 0, "syn_dropped": 0,
                      "intervals_ms": [], "dispatch_delay_ms": [], "last_ns": None, "tail": b""}
            try:
                fd = os.open(d["path"], os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
                if d["kind"] == "evdev":
                    try:
                        fcntl.ioctl(fd, EVIOCSCLOCKID, struct.pack("i", 1))
                        record["kernel_clock"] = "CLOCK_MONOTONIC"
                    except OSError as e:
                        record["kernel_clock"] = f"unavailable ({e.strerror})"
                self.selector.register(fd, selectors.EVENT_READ, record)
                record["fd"] = fd
                self.devices.append(record)
                self.status.append({**d, "status": "opened", "clock": record.get("kernel_clock")})
            except OSError as e:
                self.status.append({**d, "status": f"unavailable: {e.strerror}"})

    def sample(self, timeout):
        for key, _mask in self.selector.select(timeout):
            d = key.data
            try:
                chunk = os.read(key.fd, 8192)
                now = time.monotonic_ns()
                if not chunk:
                    continue
                if d["kind"] == "hidraw":
                    # hidraw read() returns one report; no coordinates/button payload persisted.
                    self.mark(d, now)
                else:
                    d["tail"] += chunk
                    while len(d["tail"]) >= EVENT.size:
                        packet, d["tail"] = d["tail"][:EVENT.size], d["tail"][EVENT.size:]
                        sec, usec, typ, code, value = EVENT.unpack(packet)
                        if typ == 0 and code == 0:  # SYN_REPORT (only on changed evdev state)
                            event_ns = (sec * 1_000_000 + usec) * 1_000
                            # Only calculate kernel-to-observer delay if clock match established.
                            if d.get("kernel_clock") == "CLOCK_MONOTONIC" and 0 <= now-event_ns < 5_000_000_000:
                                d["dispatch_delay_ms"].append((now-event_ns)/1_000_000)
                            self.mark(d, event_ns if d.get("kernel_clock") == "CLOCK_MONOTONIC" else now)
                        elif typ == 0 and code == 3:  # SYN_DROPPED: OUR evdev client queue overflowed.
                            d["syn_dropped"] += 1
                        elif typ == 1:
                            if value in (0, 1, 2):
                                d[{0: "key_up", 1: "key_down", 2: "key_repeat"}[value]] += 1
                                if code == 330:  # BTN_TOUCH, if this evdev interface carries it
                                    d["pen_touch_down" if value == 1 else "pen_touch_up"] += (value != 2)
            except BlockingIOError:
                pass
            except OSError as e:
                self.status.append({"path": d["path"], "status": f"read error: {e.strerror}"})
                try:
                    self.selector.unregister(key.fd)
                except (KeyError, ValueError):
                    pass

    @staticmethod
    def mark(d, ns):
        if d["last_ns"] is not None and ns >= d["last_ns"]:
            d["intervals_ms"].append((ns - d["last_ns"]) / 1_000_000)
        d["last_ns"] = ns
        d["reports"] += 1

    def result(self):
        output = []
        for d in self.devices:
            periods = d["intervals_ms"]
            output.append({"kind": d["kind"], "path": d["path"], "name": d["name"],
                           "reports": d["reports"], "key_down": d["key_down"], "key_up": d["key_up"],
                           "key_repeat": d["key_repeat"], "pen_touch_down": d["pen_touch_down"],
                           "pen_touch_up": d["pen_touch_up"], "syn_dropped": d["syn_dropped"],
                           "period_ms": dist(periods), "observer_delay_ms": dist(d["dispatch_delay_ms"]),
                           "histogram": histogram(periods, 0, 12, 0.5),
                           "interpretation": "hidraw userspace read intervals" if d["kind"] == "hidraw"
                           else "evdev SYN_REPORT intervals (state changes, not fixed USB poll)"})
        for key in list(self.selector.get_map().values()):
            try:
                self.selector.unregister(key.fileobj)
                os.close(key.fileobj)
            except OSError:
                pass
        self.selector.close()
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
    mon = next((x for x in monitors if x.get("name") == MONITOR), None)
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
            for name in PERF_FILES:
                p = folder / name
                if p.is_file():
                    result[str(p)] = p.stat().st_size
    return result


def copy_perf_log_deltas(out, start, end):
    logdir = out / "performance-logs"
    logdir.mkdir(mode=0o700, exist_ok=True)
    results = []
    for path, size in end.items():
        p = Path(path)
        try:
            current = p.stat().st_size
            offset = start.get(path, 0)
            if current < offset:
                offset = 0  # rotated/replaced
            cap = 2_000_000
            truncated = current - offset > cap
            if truncated:
                offset = current - cap
            if current <= offset:
                continue
            with p.open("rb") as source:
                source.seek(offset)
                payload = source.read(cap)
            dest = logdir / p.name
            dest.write_bytes(payload)
            results.append({"source": str(p), "copied_bytes": len(payload), "truncated": truncated,
                            "saved": str(dest.relative_to(out))})
        except OSError:
            pass
    return results


def parse_slow_logs(root):
    result = {}
    for name in PERF_FILES:
        p = Path(root) / "performance-logs" / name
        if not p.is_file():
            continue
        content = p.read_text(errors="replace")
        matches = [float(x.replace(",", "")) for x in re.findall(r"Frame length\s*:\s*([\d,.]+)\s*ms", content, re.I)]
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
        rows.setdefault(name, []).append({"err": err, "quantum": quantum, "rate": rate})
    return {"nodes": {name: {"observations": len(v), "first_err": v[0]["err"], "last_err": v[-1]["err"],
                             "delta_err": max(0, v[-1]["err"] - v[0]["err"]),
                             "graph_quantum": v[-1]["quantum"], "graph_rate": v[-1]["rate"]} for name, v in rows.items()},
            "status": "parsed" if rows else "raw_capture_only"}


def analyze(data):
    samples = data.get("samples", [])
    temps = [x["cpu"]["temp_C"] for x in samples if isinstance(x.get("cpu", {}).get("temp_C"), (int, float))]
    throttles = [x["cpu"]["throttle_count"] for x in samples if isinstance(x.get("cpu", {}).get("throttle_count"), int)]
    eligible, dso, torn = 0, 0, 0
    dso_blockers, tearing_blockers = Counter(), Counter()
    for item in samples:
        disp = item.get("display") or {}
        win, mon = disp.get("window") or {}, disp.get("monitor") or {}
        if (win.get("class") in ("osu!", "osu-lazer") and win.get("fullscreen") == 2 and
                win.get("fullscreenClient") == 0 and mon.get("name") == MONITOR):
            eligible += 1
            active_dso = str(mon.get("directScanoutTo", "0")) not in ("0", "", "None", "null")
            if active_dso:
                dso += 1
                if mon.get("activelyTearing") is True:
                    torn += 1
            else:
                for reason in mon.get("directScanoutBlockedBy") or []:
                    dso_blockers[str(reason)] += 1
            if mon.get("activelyTearing") is not True:
                for reason in mon.get("tearingBlockedBy") or []:
                    tearing_blockers[str(reason)] += 1
    tasks = {}
    for item in samples:
        for th in item.get("threads", []):
            tasks.setdefault((th["tid"], th["name"]), []).append(th)
    threads = []
    for (tid, name), rows in tasks.items():
        if len(rows) < 2:
            continue
        a, b = rows[0], rows[-1]
        waits, runs, slices = b["wait_ns"] - a["wait_ns"], b["run_ns"] - a["run_ns"], b["slices"] - a["slices"]
        if waits >= 0 and runs >= 0 and slices >= 0:
            threads.append({"tid": tid, "name": name, "run_ms": round(runs / 1e6, 3),
                            "runqueue_wait_ms": round(waits / 1e6, 3), "slices": slices,
                            "wait_per_slice_ms": round(waits / 1e6 / slices, 4) if slices else None,
                            "note": "runqueue wait / scheduling slices (not event-to-Update latency)"})
    threads.sort(key=lambda x: x["runqueue_wait_ms"], reverse=True)
    input_data = data.get("input", {})
    return {"input": input_data, "audio": {"alsa_start": data.get("alsa_start"),
                                            "alsa_end": data.get("alsa_end"),
                                            "pw_start": data.get("pw_start"),
                                            "pw_end": data.get("pw_end"),
                                            "pw_top": data.get("pw_top")},
            "update": {"thread_sched": threads, "game_log": data.get("game_log", {}),
                       "note": "No per-frame Update latency histogram from procfs; only kernel scheduler aggregates and slow-frame logs."},
            "draw": {"eligible_samples": eligible, "dso_samples": dso,
                     "actively_tearing_samples": torn,
                     "dso_blockers": dict(dso_blockers),
                     "tearing_blockers": dict(tearing_blockers),
                     "dso_ratio": round(dso / eligible * 100, 1) if eligible else None,
                     "tearing_ratio_among_dso": round(torn / dso * 100, 1) if dso else None,
                     "note": "Hyprland sampled state, not actual async KMS-flip success or optical latency."},
            "system": {"temp_C": dist(temps), "throttle_delta": max(0, throttles[-1] - throttles[0]) if len(throttles) >= 2 else None,
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
    hist = []
    for d in devices:
        vals = d["period_ms"]
        main_table.append((d["path"], d["kind"], d["reports"], fmt(vals["p50"], 3), fmt(vals["p95"], 3),
                           fmt(vals["p99"], 3), fmt(vals["p99_9"], 3),
                           d["syn_dropped"], d["key_down"], d["key_up"]))
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
    rows_sched = [(x["tid"], x["name"], fmt(x["run_ms"]), fmt(x["runqueue_wait_ms"]), x["slices"], fmt(x["wait_per_slice_ms"], 4))
                  for x in summary["update"]["thread_sched"][:20]]
    alsa = summary["audio"].get("alsa_end") or {}
    pcm_rows = [(x["path"], x["params"].replace('\n', '; ')) for x in alsa.get("open_playback_pcms", [])]
    pw = summary["audio"].get("pw_top") or {}
    pwrows = [(k, v["observations"], v.get("graph_quantum"), v.get("graph_rate"), v["delta_err"]) for k,v in pw.get("nodes", {}).items()]
    nodeprops = (summary["audio"].get("pw_end") or {}).get("nodes", [])
    prop_rows = [(x.get("id"), x.get("props", {}).get("node.name"), x.get("props", {}).get("api.alsa.period-size"),
                  x.get("props", {}).get("api.alsa.period-num"), x.get("props", {}).get("api.alsa.headroom")) for x in nodeprops]
    gap = '無効' if not proc.get("pid") else '観測済み'
    warnings = ["生ログには端末名、スレッド名、アプリ情報が含まれます。公開前に確認してください。",
                "単独の短時間計測では優劣を判定できません。8x/Unlimited、BASS -128/-256は同条件の別runで比較してください。",
                "Input→Updateイベント別待機時間、BASS実効内部周期、音の物理的開始、DRM Flip時刻、光学的Input-to-photonは本キットでは未測定です。"]
    config = data.get('config', {})
    title = f'osu! latency lab | {config.get("label", "untitled")}'
    style = '''
:root{color-scheme:dark;font-family:ui-sans-serif,system-ui,sans-serif;background:#0e1520;color:#e7edf3}
body{max-width:1170px;margin:auto;padding:24px 24px 75px;line-height:1.65}header{border-bottom:1px solid #334155;padding:20px 0 28px}h1{letter-spacing:-.03em;font-size:2rem}h2{margin-top:0;font-size:1.25rem}h3{font-size:1rem;color:#bdd4e5}.intro,.muted,.micro{color:#a5b4c3}.micro{font-size:.79rem}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(225px,1fr));gap:14px}.metric{background:#182333;border:1px solid #334457;padding:17px;border-radius:12px;min-height:130px;display:flex;flex-direction:column}.mname{color:#aabacf;font-size:.85rem}.mvalue{font-size:1.8rem;font-weight:700;font-variant-numeric:tabular-nums}.kind{font:600 .66rem system-ui;color:#8dc8d4;margin-top:auto;letter-spacing:.03em;text-transform:uppercase}.kind.proxy{color:#eed09b}.kind.unknown{color:#d1a7a7}section{margin-top:22px;border:1px solid #304156;border-radius:15px;padding:22px;background:#111d2a}.tabwrap{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:.85rem}th,td{padding:10px 12px;border-bottom:1px solid #304156;text-align:left;vertical-align:top}th{color:#95b3c4}svg{max-width:100%;height:auto}.warning{border-left:3px solid #c9a66b;padding:9px 14px;margin:10px 0;background:#202533}.tag{font-size:.74rem;color:#86c6d1;border:1px solid #447781;border-radius:5px;padding:3px 7px;margin-right:8px}code{color:#b9dbdf}ul{padding-left:20px}details{margin-top:8px}a{color:#92d6e7}'''
    body = [f'<header><span class="tag">MEASUREMENT / not a latency proof</span><span class="tag">{esc(config.get("label"))}</span><h1>{esc(title)}</h1>'
            f'<p class="intro">{esc(data.get("started"))}〜{esc(data.get("ended"))} ／ 計測 {esc(config.get("seconds"))}秒 ／ '
            f'公式osu!無改変・root権限不要・Inputは読み取りのみ</p></header>']
    body.append('<section><h2>結論の見取り図</h2><div class="grid">')
    body += [metric('Input: 接続済デバイス',f'{len(devices)} 台','hidrawとevdevを区別 / 実入力待ち時間は未知'),
             metric('Audio: BASS要求値', pill(env.get('OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD')),
                    'プロセス環境変数。実効内部periodではありません', 'proxy'),
             metric('Update: ゲームスレッド',pill(len(summary['update']['thread_sched']) if proc.get('pid') else None),'proc schedstat / 個別Update周期のp99ではありません','proxy'),
             metric('Draw: 既知条件でのDSO',fmt(dra['dso_ratio'],1)+'%' if dra['dso_ratio'] is not None else '未測定',
                    f'{dra["dso_samples"]}/{dra["eligible_samples"]} samples | 1秒間隔'),
             metric('Draw: tearing状態',fmt(dra['tearing_ratio_among_dso'],1)+'%' if dra['tearing_ratio_among_dso'] is not None else '未測定',
                    'GPU非同期Flip成功の証拠ではありません','proxy'),
             metric('CPU最大温度',fmt(sysd['temp_C']['max'])+'°C' if sysd['temp_C']['max'] is not None else '未測定',
                    f'package throttle増分 {pill(sysd["throttle_delta"])}')]
    body.append('</div></section>')
    body.append('<section><h2>Input <span class="kind">device intervals</span></h2>')
    body.append('<p class="intro">CTL-472は現在400Hzを目標（公称2.5ms）。ヒストグラムは実際に観測できた報告の間隔で、静止時の空白は取りこぼしの証拠ではありません。ペンクリック成功率やInput→Update遅延は測定できません。</p>')
    body.append('<div class="tabwrap">'+simple_table(['デバイス','経路','報告数','p50 ms','p95 ms','p99 ms','p99.9 ms','SYN_DROPPED','press','release'],main_table)+'</div>')
    body+=hist
    body.append('<details><summary>デバイスのアクセス状態</summary><pre>'+esc(json.dumps(input_summary.get('status'),ensure_ascii=False,indent=2))+'</pre></details></section>')
    body.append('<section><h2>Audio <span class="kind proxy">driver/proxy</span></h2>')
    body.append('<p class="intro">BASSは要求値のみ確認。実効ALSA hw_paramsはPCMが開いている場合に限り取得。PipeWire ERRはXRunとその他のエラーの合計であり、ゼロ以外なら原因調査が必要です。</p>')
    body.append('<h3>開いているALSA playback PCM</h3><div class="tabwrap">'+simple_table(['PCM','hw_params'],pcm_rows)+'</div>')
    body.append('<h3>PipeWireノードの要求値</h3><div class="tabwrap">'+simple_table(['ID','ノード','period-size','period-num','headroom'],prop_rows)+'</div>')
    body.append('<h3>pw-top Graph / ERR</h3><div class="tabwrap">'+simple_table(['Node','観測行数','QUANT','RATE','ERR増分'],pwrows)+'</div><p class="micro">QUANT/RATEはPipeWire graph/streamの処理周期の観測値。BASS periodやALSA DMA bufferとは別です。</p></section>')
    body.append('<section><h2>Update <span class="kind proxy">scheduler/slow-frame</span></h2>')
    body.append('<p class="intro">procfsのschedstatで累積runqueue待機時間を記録します。Updateフレーム周期分布は別物です。Ctrl+F2のperformanceログは遅延フレームの選択的ログであり、全フレームp99は算出しません。</p>')
    body.append(f'<p class="micro">PID {esc(proc.get("pid"))} / cgroup {esc(proc.get("cgroup"))} / timerslack {esc(proc.get("timerslack_ns"))}ns / '
                f'cpu.weight {esc(proc.get("scope_props",{}).get("cpu.weight"))} / cpu.uclamp.min {esc(proc.get("scope_props",{}).get("cpu.uclamp.min"))}</p>')
    body.append('<div class="tabwrap">'+simple_table(['TID','name','CPU run ms','runqueue wait ms','slices','wait/slice ms'],rows_sched)+'</div>')
    body.append('<h3>osu!公式performanceログのslow frame</h3><div class="tabwrap">'+simple_table(['ログ','slow frame数','最大ms（整数ログ値）'],rows)+'</div></section>')
    body.append('<section><h2>Draw <span class="kind">DSO state</span></h2>')
    body.append('<p class="intro">fullscreen 2/0が成立しているサンプルのみを母数にします。HyprlandのactivelyTearingはアプリの表示モード判断の状態で、i915の実flip時刻、描画フレーム時間、光学遅延は表しません。</p>')
    body.append('<div class="grid">'+metric('2/0条件成立',dra['eligible_samples'],'1Hzの状態サンプル')+
                metric('Direct Scanout',dra['dso_samples'],'2/0条件成立内')+
                metric('activelyTearing',dra['actively_tearing_samples'],'DSO状態のうちtrue', 'proxy')+'</div>')
    body.append('<h3>DSOが阻害された理由（既知2/0条件内）</h3>'+simple_table(['reason','samples'],list(dra.get('dso_blockers',{}).items())))
    body.append('<h3>Tearingが阻害された理由（既知2/0条件内）</h3>'+simple_table(['reason','samples'],list(dra.get('tearing_blockers',{}).items()))+'</section>')
    body.append('<section><h2>熱・P-state</h2>'+svg_temps(data.get('samples',[]))+
                f'<p class="micro">温度p95 {fmt(sysd["temp_C"]["p95"])}°C ／ throttle増分 {pill(sysd["throttle_delta"])} ／ CPU周波数p50 {fmt(sysd["cpu_kHz"]["p50"],0)} kHz</p></section>')
    body.append('<section><h2>測定の限界と次の比較</h2>')
    for message in warnings:
        body.append('<div class="warning">'+esc(message)+'</div>')
    body.append('<p class="intro">比較は同一譜面・同じプレイ時間・同じペン操作・同一のDiscord/配信条件で実施。まず400Hz/-128/8x/同期提示をベースラインとして記録し、1条件ずつ変えます。結果は <code>osu-lab compare sessionA sessionB</code> で重ねて表示します。</p></section>')
    return '<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+esc(title)+'</title><style>'+style+'</style><body>'+''.join(body)+'</body></html>'


def comparison_html(entries):
    summaries = [x["analysis"] for x in entries]
    labels = [x["config"]["label"] for x in entries]
    def obtain(x, kind):
        if kind == "dso":return x["draw"]["dso_ratio"]
        if kind == "tear":return x["draw"]["tearing_ratio_among_dso"]
        if kind == "temp":return x["system"]["temp_C"]["max"]
        if kind == "throttle":return x["system"]["throttle_delta"]
        if kind == "sched":
            xs=[t for t in x["update"]["thread_sched"] if re.search("update",t["name"],re.I)]
            return xs[0]["wait_per_slice_ms"] if xs else None
        if kind == "err":
            vals=[r["delta_err"] for k,r in x["audio"]["pw_top"].get("nodes",{}).items() if "alsa_output" in k]
            return sum(vals) if vals else None
        if kind == "input":
            matches=[d for d in x["input"]["devices"] if d["kind"]=="hidraw"]
            return matches[0]["period_ms"]["p50"] if matches else None
    metrics=[("Input: hidraw中央値（ms）", "input", "測定した報告間隔。低い値だけでクリック品質を判定しない"),
             ("Audio: ALSA ERR増分", "err", "XRun以外のエラーを含む。稼働時間をそろえる"),
             ("Update: Update runqueue wait/slice（ms）", "sched", "スレッド名が特定できた場合の代理指標"),
             ("Draw: DSO率（%）", "dso", "2/0条件が母数。高いほど安定"),
             ("Draw: tearing状態率（%）", "tear", "高いことが低遅延の光学的証明とはならない"),
             ("CPU最高温度（°C）", "temp", "温度負荷条件が同じか確認"),
             ("スロットリング増分", "throttle", "0が望ましい")]
    rows=[]
    for title,key,note in metrics:
        values=[obtain(x,key) for x in summaries]
        columns=[fmt(v,3) for v in values]
        if len(values)==2:
            delta=round(values[1]-values[0],3) if all(isinstance(v,(int,float)) for v in values) else None
            columns.append(f"{delta:+.3f}" if delta is not None else "未判定")
        rows.append((title,*columns,note))
    body=f'<header><h1>osu! latency lab · comparison</h1><p class="intro">実測可能な指標のみ横並び。数値が良くても入力→光学遅延改善を意味しません。</p></header>'
    cols=['指標',*labels]+(['Δ（右−左）'] if len(labels)==2 else [])+['解釈']
    body+='<section><h2>実行条件の比較</h2><div class="tabwrap">'+simple_table(cols,rows)+'</div></section>'
    body+='<section><h2>採用判断</h2><p>CTL-472は400Hzを基準とし、1000Hzとの比較ではクリック反応の信頼性を優先してください。AudioはERR増分0、DrawはDSO維持が必要条件です。Updateの実効p99や物理的遅延は、この比較表では未知のままです。</p></section>'
    return '<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:15px/1.7 system-ui;color:#e9eff5;background:#101925;max-width:1150px;margin:auto;padding:24px}.intro{color:#99b2c9}section{background:#162333;border:1px solid #405064;border-radius:12px;padding:20px;margin-top:20px}.tabwrap{overflow:auto}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #314457;padding:11px;text-align:left}th{color:#9ad4df}</style><body>'+body+'</body></html>'


def terminate(signum, _frame):
    global STOP
    STOP = True


def capture(args):
    global STOP
    STOP = False
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,60}", args.label):
        raise SystemExit("label must be 1..61 safe ASCII letters/digits/._-")
    if args.seconds < 10 or args.seconds > 600:
        raise SystemExit("--seconds must be 10..600")
    root = Path(args.out).expanduser().resolve()
    if not root.exists():
        root.mkdir(parents=True, mode=0o700)
    elif not root.is_dir():
        raise SystemExit(f"--out is not a directory: {root}")
    # Do not change permissions on a pre-existing directory, including Downloads.
    # New per-session directories are always private (0700).
    out = root / f"{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}-{args.label}"
    out.mkdir(mode=0o700, exist_ok=False)
    start_s = stamp()
    start_log = find_perf_logs(args.logs)
    observer = InputObserver(args.hidraw, args.event)
    pid = proc_pid(args.pid)
    proc = proc_snapshot(pid)
    data = {"version": VERSION, "started": start_s,
            "config": {"label": args.label, "seconds": args.seconds, "expected_tablet_hz": args.tablet_hz,
                       "game_settings": args.game_settings, "expected_bass": args.bass,
                       "note": args.note}, "proc_start": proc,
            "alsa_start": alsa_snapshot(), "pw_start": pw_dump_snapshot(), "samples": []}
    pw_process = None
    pw_file = None
    if shutil.which("pw-top"):
        try:
            pw_file = (out / "pw-top-batch.txt").open("w", encoding="utf-8")
            pw_process = subprocess.Popen(["pw-top", "-b", "-n", str(args.seconds+3)],
                                          stdout=pw_file, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            if pw_file: pw_file.close()
            pw_file = None
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, terminate)
    print(f"osu-lab capture → {out}\n"
          f"Keep osu! foreground for {args.seconds}s; input is passive read-only.\n"
          f"Expected CTL-472 setting: {args.tablet_hz}Hz (metadata, not assumed measured).", file=sys.stderr, flush=True)
    start = time.monotonic()
    next_tick = start
    end = start+args.seconds
    try:
        while not STOP and time.monotonic() < end:
            now = time.monotonic()
            if now >= next_tick:
                data["samples"].append({"elapsed_s": round(now-start, 3),
                                        "display": display_snapshot(), "cpu": cpu_snapshot(),
                                        "threads": task_snapshot(pid)})
                next_tick += 1.0
                if next_tick < now:
                    next_tick = now + 1.0
            observer.sample(max(0, min(0.05, next_tick-time.monotonic(), end-time.monotonic())))
    finally:
        data["input"] = observer.result()
        if pw_process:
            try:
                pw_process.terminate()
                pw_process.wait(timeout=2)
            except (OSError, subprocess.TimeoutExpired):
                pw_process.kill()
                pw_process.wait(timeout=2)
        if pw_file: pw_file.close()
        data["ended"] = stamp()
        data["alsa_end"] = alsa_snapshot()
        data["pw_end"] = pw_dump_snapshot()
        data["pw_top"] = parse_pw_top(out / "pw-top-batch.txt")
        data["log_capture"] = copy_perf_log_deltas(out, start_log, find_perf_logs(args.logs))
        data["game_log"] = parse_slow_logs(out)
        write_json(out / "data.json", data)
        ana = analyze(data)
        write_json(out / "analysis.json", ana)
        (out / "report.html").write_text(html_report(data, ana), encoding="utf-8")
        print(f"Saved {len(data['samples'])} system samples; "
              f"report: {out/'report.html'}\n"
              f"Private raw evidence: {out/'data.json'}", file=sys.stderr)
    return 130 if STOP else 0


def report(args):
    root = Path(args.session)
    data = json.loads((root / "data.json").read_text(encoding="utf-8"))
    ana = analyze(data)
    write_json(root / "analysis.json", ana)
    (root / "report.html").write_text(html_report(data, ana), encoding="utf-8")
    print(root / "report.html")
    return 0


def compare(args):
    entries = []
    for folder in args.sessions:
        root = Path(folder).expanduser().resolve()
        data = json.loads((root / "data.json").read_text(encoding="utf-8"))
        entries.append({"config": data["config"], "analysis": analyze(data)})
    root = Path(args.out).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    dest = root / "comparison.html"
    dest.write_text(comparison_html(entries), encoding="utf-8")
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
