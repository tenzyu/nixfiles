#!/usr/bin/env python3
"""Independent, read-only SplitCast performance collection and strict comparison.

collect observes existing PIDs. It never starts or stops a workload. Frame CSV is
an external recording with exact columns elapsed_s,frame_time_ms, relative to the
same measurement window. No FPS-to-p99 estimation or implicit MangoHud units.
compare requires six files; compare-series requires three files from one series.
All runs must be at least 600 seconds.
See conditions.example.json for the explicit nonsecret environment contract.

Standalone setup: python3 perf.py init-conditions --output conditions.json
then review/fill the remaining REPLACE values before collecting.
"""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
import time

CONDITIONS = ("game_only", "obs_current", "splitcast")
SERIES = ("baseline", "new")
COMMON_KEYS = {
    "replay_sha256", "game_version", "hardware_id", "kernel", "cpu_count",
    "fps_cap", "resolution", "osu_mode", "background_profile", "environment_flags",
}
FLAG_KEYS = {"gamemode", "vsync", "power_profile", "session_type", "capture_scope"}
WORKLOAD_KEYS = {"capture_flags", "encoder_flags", "obs_profile_sha256", "versions"}


class EvidenceError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise EvidenceError(message)


def number(value):
    return isinstance(value, (float, int)) and not isinstance(value, bool) and math.isfinite(value)


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")


def create(path, value):
    """Create a new artifact without ever replacing an existing path."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as output:
        output.write(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")


def conditions_template():
    """Return the example contract with collector-host facts prefilled."""
    template = Path(__file__).with_name("conditions.example.json")
    value = load(template)
    value["common"]["kernel"] = platform.release()
    value["common"]["cpu_count"] = os.cpu_count()
    return value


def conditions(value, check_host=True):
    require(set(value) == {"common", "workload"}, "conditions need common and workload only")
    common, workload = value["common"], value["workload"]
    require(set(common) == COMMON_KEYS, "missing/unknown common conditions")
    require(set(common["environment_flags"]) == FLAG_KEYS, "explicit environment flags required")
    require(set(workload) == set(CONDITIONS), "all three workload conditions required")
    for scenario in workload.values():
        require(set(scenario) == WORKLOAD_KEYS, "missing/unknown workload conditions")
        require(isinstance(scenario["versions"], dict) and scenario["versions"], "workload versions required")
        require(all(isinstance(scenario[k], str) and scenario[k] not in ("", "REPLACE") for k in WORKLOAD_KEYS - {"versions"}), "empty workload flags/profile")
        require(all(isinstance(v, str) and v not in ("", "REPLACE") for v in scenario["versions"].values()), "empty workload versions")
    require(isinstance(common["cpu_count"], int) and common["cpu_count"] > 0, "invalid cpu_count")
    require(isinstance(common["fps_cap"], int) and common["fps_cap"] >= 0, "invalid fps_cap (0 means uncapped)")
    require(isinstance(common["resolution"], str) and re.fullmatch(r"[1-9][0-9]*x[1-9][0-9]*", common["resolution"]), "resolution must be WIDTHxHEIGHT")
    require(all(isinstance(v, str) and v not in ("", "REPLACE") for v in common["environment_flags"].values()), "empty environment flags")
    if check_host:
        require(common["cpu_count"] == os.cpu_count(), "cpu_count differs from collector host")
        require(common["kernel"] == platform.release(), "kernel differs from collector host")
    require(len(common["replay_sha256"]) == 64 and all(c in "0123456789abcdef" for c in common["replay_sha256"]), "replay SHA256 required")
    # The explicit input is never an environment dump or command argv capture.
    text = json.dumps(value)
    require(not any(x in text.lower() for x in ("password", "secret", "oauth", "token", "stream_key", "://")), "credential-like conditions rejected")
    require(all(common[k] not in (None, "", "REPLACE") for k in COMMON_KEYS), "empty conditions")
    return value


def read_stat(path):
    text = Path(path).read_text()
    pid = int(text.split("(", 1)[0])
    fields = text.rsplit(")", 1)[1].split()
    return {"pid": pid, "ppid": int(fields[1]), "start": int(fields[19]),
            "ticks": int(fields[11]) + int(fields[12])}


def process_table(root=Path("/proc")):
    table = {}
    for path in root.glob("[0-9]*/stat"):
        try:
            item = read_stat(path)
            table[item["pid"]] = item
        except (FileNotFoundError, ProcessLookupError):
            continue
    return table


class ProcessTree:
    def __init__(self, roots, boot_id, initial):
        self.boot_id = boot_id
        self.roots = {pid: initial[pid]["start"] for pid in roots}
        self.known = {}
        self.first = True

    def sample(self, table):
        errors = []
        selected = set()
        for pid, start in self.roots.items():
            if pid not in table or table[pid]["start"] != start:
                errors.append("root_missing_or_reused")
            else:
                selected.add(pid)
        for pid, item in table.items():
            if (pid, item["start"]) in self.known:
                selected.add(pid)
        while True:
            children = {pid for pid, item in table.items() if item["ppid"] in selected}
            if children <= selected:
                break
            selected |= children
        present = {(pid, table[pid]["start"]) for pid in selected}
        for identity in self.known.keys() - present:
            errors.append("descendant_missing_or_reused")
        delta = 0
        for pid, start in sorted(present):
            ticks = table[pid]["ticks"]
            identity = (pid, start)
            previous = self.known.get(identity, ticks if self.first else 0)
            if ticks < previous:
                errors.append("cpu_counter_regressed")
            else:
                delta += ticks - previous
            self.known[identity] = ticks
        self.first = False
        identities = [f"{self.boot_id}:{pid}:{start}" for pid, start in sorted(present)]
        return delta, identities, errors


def system_ticks():
    fields = Path("/proc/stat").read_text().splitlines()[0].split()[1:9]
    ticks = list(map(int, fields))
    return sum(ticks), ticks[3] + ticks[4]


def command_json(argv):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=10, check=False)
        if result.returncode:
            return {"status": "ERROR", "exit_code": result.returncode}
        return {"status": "PASS", "value": json.loads(result.stdout)}
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return {"status": "UNAVAILABLE"}


def tailscale_summary(peer):
    status = command_json(["tailscale", "status", "--json"])
    if status["status"] != "PASS":
        return status
    peers = status["value"].get("Peer", {}).values()
    matches = [p for p in peers if peer in (p.get("HostName"), p.get("DNSName")) or peer in p.get("TailscaleIPs", [])]
    if len(matches) != 1:
        return {"status": "ERROR", "reason": "peer_not_unique_or_missing"}
    p = matches[0]
    active = p.get("Online") is True and p.get("Active") is True
    return {"status": "PASS", "online": p.get("Online"), "active": p.get("Active"),
            "path": "direct" if active and p.get("CurAddr") else "relay" if active and p.get("Relay") else "unknown",
            "observation": "tailscale status snapshot; inactive peers do not establish a current path",
            "relay_region": p.get("Relay") or None,
            "tx_bytes": p.get("TxBytes"), "rx_bytes": p.get("RxBytes")}


def route_summary():
    result = command_json(["pw-dump"])
    if result["status"] != "PASS":
        return result
    nodes, links = [], []
    for item in result["value"]:
        props = (item.get("info") or {}).get("props", {})
        if item.get("type") == "PipeWire:Interface:Node":
            nodes.append({"id": item["id"], "media_class": props.get("media.class"),
                          "node_name_sha256": hashlib.sha256(str(props.get("node.name", "")).encode()).hexdigest()})
        if item.get("type") == "PipeWire:Interface:Link":
            links.append({k: props.get(k) for k in ("link.input.node", "link.input.port", "link.output.node", "link.output.port")})
    return {"status": "PASS", "nodes": nodes, "links": links,
            "privacy": "names hashed; no arbitrary properties or device metadata"}


def gpu_samples(path):
    """Read intel_gpu_top -J output. Preserve engine names, never sum engines."""
    text = Path(path).read_text().strip()
    try:
        values = json.loads(text)
    except ValueError:
        # intel_gpu_top versions can emit a JSON object stream rather than an array.
        values, index = [], 0
        decoder = json.JSONDecoder()
        while index < len(text):
            while index < len(text) and text[index].isspace():
                index += 1
            if index == len(text):
                break
            value, index = decoder.raw_decode(text, index)
            values.append(value)
    if isinstance(values, dict):
        values = [values]
    require(isinstance(values, list) and values, "missing GPU samples")
    engines = {}
    engine_names = None
    for value in values:
        require(isinstance(value.get("engines"), dict), "GPU sample missing engines")
        names = set(value["engines"])
        if engine_names is None:
            engine_names = names
        require(names == engine_names, "GPU sample missing an engine")
        for name, engine in value["engines"].items():
            busy = engine.get("busy")
            require(number(busy) and 0 <= busy <= 100, "invalid Intel engine busy sample")
            engines.setdefault(name, []).append(busy)
    require(any("render" in k.lower() or "3d" in k.lower() for k in engines), "GPU render engine missing")
    require(any("video" in k.lower() for k in engines), "GPU Video engine missing")
    return {k: {"samples": len(v), "mean_busy_percent": statistics.mean(v), "max_busy_percent": max(v)} for k, v in engines.items()}


def gpu_evidence(path):
    """Summarize external GPU data without claiming window alignment."""
    return {"status": "UNVERIFIED", "engines": gpu_samples(path),
            "coverage": "external input; alignment with the CPU measurement window is not verified"}


def frame_times(path, duration):
    with Path(path).open(newline="") as handle:
        reader = csv.DictReader(handle)
        require(reader.fieldnames == ["elapsed_s", "frame_time_ms"], "expected exact external CSV header elapsed_s,frame_time_ms")
        rows = [(float(r["elapsed_s"]), float(r["frame_time_ms"])) for r in reader]
    require(len(rows) >= 2, "missing frame samples")
    require(all(number(t) and number(ms) and t >= 0 and ms > 0 for t, ms in rows), "invalid frame samples")
    require(rows[0][0] <= 0.25 and rows[-1][0] >= duration - 0.25, "frame CSV does not cover measurement window")
    require(rows[-1][0] <= duration + 0.25, "frame CSV exceeds measurement window")
    for (a, _), (b, ms) in zip(rows, rows[1:]):
        require(0 < b - a <= max(0.25, ms / 1000 * 2), "missing/out-of-order frame samples")
    require(abs(sum(ms for _, ms in rows) / 1000 - duration) <= max(0.5, duration * 0.01), "frame durations do not account for measurement window")
    values = sorted(ms for _, ms in rows)
    return {"source": "external_csv", "unit": "ms", "method": "nearest_rank",
            "samples": len(values), "coverage_s": rows[-1][0] - rows[0][0],
            "p99_ms": values[math.ceil(len(values) * 0.99) - 1],
            "sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest()}


def version(argv):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        return result.stdout.splitlines()[0] if result.returncode == 0 else "UNAVAILABLE"
    except (OSError, subprocess.TimeoutExpired, IndexError):
        return "UNAVAILABLE"


def collect(args):
    spec = conditions(load(args.conditions))
    require(args.duration >= 600 or args.instrument_smoke, "duration must be >=600s; --instrument-smoke is never comparable")
    require(args.duration > 0 and 0 < args.interval <= 5, "invalid sampling window")
    require(args.frames and args.frame_window_confirmed or args.instrument_smoke, "external frame CSV and --frame-window-confirmed required")
    initial = process_table()
    require(all(pid in initial for pid in args.pid), "root PID unavailable")
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    tracker = ProcessTree(args.pid, boot, initial)
    errors, samples = [], []
    start = time.monotonic()
    system_start, idle_start = system_ticks()
    previous = start
    while True:
        now = time.monotonic()
        delta, ids, failed = tracker.sample(process_table())
        errors.extend(failed)
        samples.append({"elapsed_s": now - start, "interval_s": now - previous,
                        "ticks": delta, "identities": ids, "errors": failed})
        previous = now
        if now - start >= args.duration:
            break
        time.sleep(min(args.interval, args.duration - (now - start)))
    end_ticks, end_idle = system_ticks()
    duration = samples[-1]["elapsed_s"]
    frame = None
    if args.frames:
        try:
            frame = frame_times(args.frames, duration)
        except (EvidenceError, ValueError, OSError, KeyError) as exc:
            errors.append("frame_input: " + str(exc))
    report = {
        "schema": 1, "kind": "performance", "series": args.series, "condition": args.condition,
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "revision": args.revision, "conditions": spec, "duration_s": duration,
        "requested_duration_s": args.duration, "interval_s": args.interval,
        "instrument_smoke": args.instrument_smoke, "clock_ticks_per_s": os.sysconf("SC_CLK_TCK"),
        "cpu_count": os.cpu_count(), "samples": samples, "frames": frame, "errors": errors,
        "system_cpu_total_percent": 100 * (1 - (end_idle - idle_start) / (end_ticks - system_start)),
        "route_dump": route_summary(),
        "network": tailscale_summary(args.peer) if args.peer else {"status": "NOT_RUN"},
        "collector_versions": {"python": platform.python_version(), "kernel": platform.release(),
                               "ffprobe": version(["ffprobe", "-version"]), "ffmpeg": version(["ffmpeg", "-version"])},
        "accounting_limits": "Polling cannot observe children born and exited between samples. Any observed disappearing process invalidates comparison. No child waited-for ticks are double counted.",
        "gpu": {"status": "NOT_RUN", "reason": "supply external intel_gpu_top -J file; no invented metrics"},
    }
    if args.intel_gpu_json:
        try:
            report["gpu"] = gpu_evidence(args.intel_gpu_json)
        except (OSError, ValueError, TypeError) as exc:
            report["gpu"] = {"status": "ERROR", "reason": str(exc)}
    save(args.output, report)
    return {"status": "RECORDED", "comparable": not errors and not args.instrument_smoke,
            "output": str(args.output), "samples": len(samples)}


def validate_run(run):
    require(run["schema"] == 1 and run["kind"] == "performance", "wrong evidence schema/kind")
    require(isinstance(run["revision"], str) and run["revision"], "missing revision")
    require(run["series"] in SERIES and run["condition"] in CONDITIONS, "unknown matrix cell")
    require(not run["instrument_smoke"], "instrument smoke is not performance evidence")
    spec = conditions(run["conditions"], check_host=False)
    duration = run["duration_s"]
    require(number(duration) and duration >= 600 and run["requested_duration_s"] >= 600, "incomplete duration (<600s)")
    require(not run["errors"], "run contains errors")
    samples = run["samples"]
    require(len(samples) >= 2, "missing CPU samples")
    require(number(run["interval_s"]) and 0 < run["interval_s"] <= 5, "invalid sampling interval")
    require(0 <= samples[0]["elapsed_s"] <= run["interval_s"], "missing initial sample")
    require(abs(samples[-1]["elapsed_s"] - duration) < 0.01, "missing final sample")
    require(samples[0]["ticks"] == 0, "initial CPU baseline must be zero")
    last_time = samples[0]["elapsed_s"]
    last_ids = set(samples[0]["identities"])
    require(last_ids, "missing process identity")
    ticks = 0
    for sample in samples:
        require(not sample["errors"] and sample["identities"], "missing/error CPU sample")
        require(number(sample["ticks"]) and sample["ticks"] >= 0, "invalid CPU ticks")
        require(last_ids <= set(sample["identities"]), "missing persistent process identity")
        last_ids = set(sample["identities"])
        t = sample["elapsed_s"]
        require(number(t) and 0 <= t - last_time <= run["interval_s"] * 1.5 + 0.05, "missing CPU interval")
        if sample is not samples[0]:
            require(t > last_time, "duplicate CPU timestamp")
        last_time = t
        ticks += sample["ticks"]
    frame = run["frames"]
    require(frame and frame["source"] == "external_csv" and frame["method"] == "nearest_rank" and frame["unit"] == "ms", "missing/unsupported frame evidence")
    require(frame["samples"] >= 2 and frame["coverage_s"] >= duration - 0.5, "missing frame coverage")
    require(number(frame["p99_ms"]) and frame["p99_ms"] > 0, "invalid p99")
    require(number(run["clock_ticks_per_s"]) and run["clock_ticks_per_s"] > 0 and run["cpu_count"] > 0, "invalid CPU denominator")
    require(run["cpu_count"] == spec["common"]["cpu_count"], "CPU count differs from conditions")
    require(number(run["system_cpu_total_percent"]) and 0 <= run["system_cpu_total_percent"] <= 100, "invalid system CPU sample")
    for optional in ("gpu", "route_dump", "network"):
        require(run[optional]["status"] not in ("ERROR", "FAIL"), optional + " contains errors")
    one_core = ticks / run["clock_ticks_per_s"] / duration * 100
    return {"process_one_core_percent": one_core, "process_machine_percent": one_core / run["cpu_count"],
            "system_cpu_total_percent": run["system_cpu_total_percent"], "p99_ms": frame["p99_ms"]}


def compare(runs):
    require(len(runs) == 6, "exactly six run files required")
    cells = {}
    reference = runs[0]
    for run in runs:
        metrics = validate_run(run)
        key = (run["series"], run["condition"])
        require(key not in cells, "duplicate matrix cell")
        require(run["conditions"] == reference["conditions"], "incomparable conditions/replay/environment/flags/versions")
        require(run["cpu_count"] == reference["cpu_count"] and run["clock_ticks_per_s"] == reference["clock_ticks_per_s"], "incomparable CPU accounting")
        require(run["collector_versions"] == reference["collector_versions"], "incomparable collector versions")
        cells[key] = metrics
    summary = {}
    for series in SERIES:
        game, obs, split = [cells[series, c] for c in CONDITIONS]
        denominator = obs["process_one_core_percent"] - game["process_one_core_percent"]
        require(denominator > 0, "invalid OBS increment denominator (must be >0)")
        increment = split["process_one_core_percent"] - game["process_one_core_percent"]
        summary[series] = {"conditions": {c: cells[series, c] for c in CONDITIONS},
                           "obs_increment_one_core_percent": denominator,
                           "splitcast_increment_one_core_percent": increment,
                           "obs_increment_reduction_percent": (denominator - increment) / denominator * 100,
                           "splitcast_p99_degradation_percent": (split["p99_ms"] / game["p99_ms"] - 1) * 100}
    changes = {c: {k: cells["new", c][k] - cells["baseline", c][k] for k in cells["new", c]} for c in CONDITIONS}
    return {"status": "COMPARABLE", "series": summary, "new_minus_baseline": changes,
            "scope": "CPU and externally recorded p99 arithmetic only. GPU engine summaries, PipeWire routes, and Tailscale status are supporting observations, not acceptance verdicts.",
            "interpretation": "Arithmetic only; no speedup or significance verdict. Repeat interleaved runs and inspect workload validity and limiter before making a performance claim."}


def compare_series(runs):
    require(len(runs) == 3, "exactly three run files required")
    require(len({run["series"] for run in runs}) == 1, "all runs must belong to the same series")
    require(len({run["revision"] for run in runs}) == 1, "all runs must use the same revision")
    cells = {}
    reference = runs[0]
    for run in runs:
        metrics = validate_run(run)
        require(run["condition"] not in cells, "duplicate condition")
        require(run["conditions"] == reference["conditions"], "incomparable conditions/replay/environment/flags/versions")
        require(run["cpu_count"] == reference["cpu_count"] and run["clock_ticks_per_s"] == reference["clock_ticks_per_s"], "incomparable CPU accounting")
        require(run["collector_versions"] == reference["collector_versions"], "incomparable collector versions")
        cells[run["condition"]] = metrics
    require(set(cells) == set(CONDITIONS), "all three conditions are required")
    game, obs, split = [cells[c] for c in CONDITIONS]
    denominator = obs["process_one_core_percent"] - game["process_one_core_percent"]
    require(denominator > 0, "invalid OBS increment denominator (must be >0)")
    increment = split["process_one_core_percent"] - game["process_one_core_percent"]
    return {"status": "COMPARABLE", "series": reference["series"],
            "conditions": cells, "obs_increment_one_core_percent": denominator,
            "splitcast_increment_one_core_percent": increment,
            "obs_increment_reduction_percent": (denominator - increment) / denominator * 100,
            "splitcast_p99_degradation_percent": (split["p99_ms"] / game["p99_ms"] - 1) * 100,
            "scope": "CPU and externally recorded p99 arithmetic only; supporting observations are not acceptance verdicts.",
            "interpretation": "Arithmetic only; no speedup or significance verdict. Repeat interleaved runs and inspect workload validity and limiter before making a performance claim."}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("init-conditions", help="write a starter conditions file with host facts filled in")
    p.add_argument("--output", required=True, help="new conditions JSON path (review and complete before collecting)")
    p = sub.add_parser("collect", help="observe existing process trees without changing them")
    p.add_argument("--conditions", required=True)
    p.add_argument("--series", choices=SERIES, required=True)
    p.add_argument("--condition", choices=CONDITIONS, required=True)
    p.add_argument("--revision", required=True)
    p.add_argument("--pid", type=int, action="append", required=True, help="one root PID per process tree; repeated allowed")
    p.add_argument("--duration", type=float, default=600)
    p.add_argument("--interval", type=float, default=1)
    p.add_argument("--frames", help="external CSV recorded over this exact window, exact header elapsed_s,frame_time_ms")
    p.add_argument("--frame-window-confirmed", action="store_true", help="operator confirms frame CSV and CPU window align to same replay interval")
    p.add_argument("--intel-gpu-json", help="optional external intel_gpu_top -J JSON, not launched by collector")
    p.add_argument("--peer", help="exact existing Tailscale peer hostname/DNS/IP; emits only selected path status and byte counters")
    p.add_argument("--instrument-smoke", action="store_true", help="allow short collector check; comparison always refuses")
    p.add_argument("--output", required=True)
    p = sub.add_parser("compare", help="strict six-cell baseline/new comparison")
    p.add_argument("runs", nargs="+")
    p.add_argument("--output", required=True)
    p = sub.add_parser("compare-series", help="strict three-condition comparison within one series")
    p.add_argument("runs", nargs="+")
    p.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        if args.command == "init-conditions":
            create(args.output, conditions_template())
            result = {"status": "CREATED", "output": str(args.output),
                      "note": "Replace every remaining REPLACE value; this is not measurement evidence."}
        elif args.command == "collect":
            result = collect(args)
        elif args.command == "compare":
            result = compare([load(p) for p in args.runs])
            create(args.output, result)
        else:
            result = compare_series([load(p) for p in args.runs])
            create(args.output, result)
    except (EvidenceError, OSError, ValueError, KeyError, TypeError) as exc:
        result = {"status": "REFUSED", "reason": str(exc)}
        if args.command in ("compare", "compare-series"):
            try:
                create(args.output, result)
            except OSError:
                pass
        print(json.dumps(result))
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
