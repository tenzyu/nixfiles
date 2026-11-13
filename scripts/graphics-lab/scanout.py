#!/usr/bin/env python3
"""Read-only Hyprland Direct Scanout sampling; do not treat state as latency."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import subprocess
import sys
import time


def scanout_value(raw: object) -> bool | None:
    if raw is None or isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw != 0
    if not isinstance(raw, str):
        return None
    token = raw.strip().lower()
    if token in ("", "(nil)", "null"):
        return None
    if token in ("0", "0x0"):
        return False
    try:
        # Hyprland represents pointers as hexadecimal, with or without 0x.
        return int(token, 16) != 0
    except ValueError:
        return None


def classify(obj: dict) -> tuple[bool | None, str]:
    value = scanout_value(obj.get("directScanoutTo"))
    blocked = obj.get("directScanoutBlockedBy")
    if value is None:
        return None, "missing/unrecognized directScanoutTo"
    if not value:
        return False, f"directScanoutTo=0, blocked={blocked!r}"
    if blocked not in (None, [], "null", ""):
        return None, f"inconsistent: scanout pointer set but blocked={blocked!r}"
    return True, "Hyprland reports direct scanout"


def extract_monitor(raw: str, name: str) -> dict:
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError("hyprctl returned non-array")
    matches = [x for x in data if isinstance(x, dict) and x.get("name") == name]
    if len(matches) != 1:
        return {"name": name, "direct": None, "note": "monitor missing/ambiguous"}
    obj = matches[0]
    direct, note = classify(obj)
    return {"name": name, "direct": direct, "note": note,
            "directScanoutTo": obj.get("directScanoutTo"),
            "directScanoutBlockedBy": obj.get("directScanoutBlockedBy"),
            "solitaryBlockedBy": obj.get("solitaryBlockedBy"),
            "activelyTearing": obj.get("activelyTearing")}


def monitor_snapshot(name: str) -> dict:
    run = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                         text=True, timeout=3, check=True)
    record = extract_monitor(run.stdout, name)
    record["at"] = datetime.now(timezone.utc).isoformat()
    return record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--monitor", required=True)
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    if not 0 < args.seconds <= 7200 or not 0.2 <= args.interval <= 60:
        parser.error("seconds must be (0,7200]; interval [0.2,60]")
    total = active = unknown = 0
    until = time.monotonic() + args.seconds
    with open(args.output, "w", encoding="utf-8") as log:
        while time.monotonic() < until:
            started = time.monotonic()
            try:
                row = monitor_snapshot(args.monitor)
            except (OSError, ValueError, subprocess.SubprocessError):
                row = {"name": args.monitor, "direct": None, "note": "hyprctl failed"}
            row["timestamp_utc"] = datetime.now(timezone.utc).isoformat()
            log.write(json.dumps(row, ensure_ascii=False) + "\n")
            log.flush()
            total += 1
            active += row["direct"] is True
            unknown += row["direct"] is None
            time.sleep(max(0, args.interval - (time.monotonic() - started)))
    print(json.dumps({"samples": total, "active": active, "unknown": unknown,
                      "active_fraction": active / total if total else None,
                      "scope": "sampled Hyprland state, not game frame latency"}))
    return 0 if total and not unknown else 2


if __name__ == "__main__":
    sys.exit(main())
