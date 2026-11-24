#!/usr/bin/env python3
"""Read-only, unprivileged memory accounting for neko5 desktop A/B trials."""
import json
import os
import re
from pathlib import Path

def meminfo():
    result = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        fields = value.split()
        if len(fields) == 2 and fields[1] == "kB":
            result[key] = int(fields[0])
    return result

def main():
    m = meminfo()
    page_kib = os.sysconf("SC_PAGE_SIZE") // 1024
    low = reserve = 0
    zones = re.split(r"(?=^Node \d+, zone)", Path("/proc/zoneinfo").read_text(), flags=re.M)
    for zone in zones:
        if not zone.startswith("Node"):
            continue
        def field(key):
            match = re.search(rf"^\s+{key}\s+(\d+)", zone, re.M)
            return int(match[1]) if match else 0
        match = re.search(r"protection:\s*\(([^)]*)\)", zone)
        protection = max(map(int, match[1].split(","))) if match else 0
        low += field("low") * page_kib
        reserve += min(field("managed"), field("high") + protection) * page_kib
    file_lru = m["Active(file)"] + m["Inactive(file)"]
    reclaimable = m.get("KReclaimable", m["SReclaimable"])
    residual = m["MemTotal"] - m["MemFree"] - file_lru - reclaimable
    actual = m["MemTotal"] - m["MemAvailable"]
    reconstructed = max(0, residual + reserve + min(file_lru // 2, low) + min(reclaimable // 2, low))
    rows = []
    unavailable = 0
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            s = (p / "smaps_rollup").read_text()
            match = re.search(r"^Pss:\s+(\d+)", s, re.M)
            if match:
                rows.append({"pid": int(p.name), "comm": (p / "comm").read_text().strip(),
                             "pss_kib": int(match[1])})
        except OSError:
            unavailable += 1
    print(json.dumps({
        "hostname": os.uname().nodename,
        "effective_uid": os.geteuid(),
        "meminfo_kib": m,
        "effective_used_mib": round(actual / 1024, 2),
        "non_cache_residual_mib": round(residual / 1024, 2),
        "estimated_reserve_mib": round(reserve / 1024, 2),
        "estimated_low_watermarks_mib": round(low / 1024, 2),
        "reconstruction_error_mib": round((actual - reconstructed) / 1024, 2),
        "pressure": {k: Path("/proc/pressure", k).read_text().strip()
                     for k in ("cpu", "memory", "io")},
        "pss_unavailable_or_exited": unavailable,
        "pss_scope": "readable processes only; not whole-system RAM",
        "processes": sorted(rows, key=lambda x: x["pss_kib"], reverse=True),
    }, indent=2))

if __name__ == "__main__":
    main()
