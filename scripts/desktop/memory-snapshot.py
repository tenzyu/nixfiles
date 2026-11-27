#!/usr/bin/env python3
"""Read-only Linux desktop memory accounting; exact KiB counters remain authoritative."""
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path


def meminfo():
    result = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        fields = value.split()
        if len(fields) == 2 and fields[1] == "kB":
            result[key] = int(fields[0])
    return result


def optional_text(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def process_pss(proc=Path("/proc")):
    rows = []
    unavailable = 0
    for p in proc.iterdir():
        if not p.name.isdigit():
            continue
        try:
            fd = os.open(p, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                with os.fdopen(os.open("smaps_rollup", os.O_RDONLY, dir_fd=fd)) as stream:
                    s = stream.read()
                match = re.search(r"^Pss:\s+(\d+)", s, re.M)
                if not match:
                    unavailable += 1
                    continue
                with os.fdopen(os.open("comm", os.O_RDONLY, dir_fd=fd), errors="replace") as stream:
                    comm = stream.read().strip()
                rows.append({"pid": int(p.name), "comm": comm,
                             "pss_kib": int(match[1]),
                             **{key.lower() + "_kib": int(found[1])
                                for key in ("Pss_Anon", "Pss_File", "Pss_Shmem")
                                if (found := re.search(rf"^{key}:\s+(\d+)", s, re.M))}})
            finally:
                os.close(fd)
        except OSError:
            unavailable += 1
    return rows, unavailable


def snapshot():
    # KPI first; process enumeration is not an atomic snapshot.
    started = time.monotonic_ns()
    m = meminfo()
    vmstat = {k: int(v) for k, v in
              (line.split() for line in Path("/proc/vmstat").read_text().splitlines())}
    pressure = {k: Path("/proc/pressure", k).read_text().strip()
                for k in ("cpu", "memory", "io")}
    identity = {
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "current_system": str(Path("/run/current-system").resolve(strict=False)),
        "booted_system": str(Path("/run/booted-system").resolve(strict=False)),
        "kernel": os.uname().release,
        "machine": os.uname().machine,
        "product": optional_text("/sys/class/dmi/id/product_name"),
        "vendor": optional_text("/sys/class/dmi/id/sys_vendor"),
        "cmdline": Path("/proc/cmdline").read_text().strip(),
    }
    timestamp = datetime.now(timezone.utc).isoformat()
    uptime = float(Path("/proc/uptime").read_text().split()[0])
    tunables = {name: optional_text("/proc/sys/vm/" + name) for name in (
        "min_free_kbytes", "watermark_scale_factor", "watermark_boost_factor",
        "lowmem_reserve_ratio", "swappiness", "vfs_cache_pressure", "page-cluster")}
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
    rows, unavailable = process_pss()
    return {
        "hostname": os.uname().nodename,
        "effective_uid": os.geteuid(),
        "identity": identity,
        "timestamp": timestamp,
        "uptime_s": uptime,
        "monotonic_ns": started,
        "vm_tunables": tunables,
        "vmstat": {k: v for k, v in vmstat.items()
                   if k.startswith(("pswp", "allocstall", "pgmajfault", "pgscan_direct"))},
        "profiling": {
            "enabled": optional_text("/proc/sys/vm/mem_profiling"),
            "compressed": optional_text("/proc/sys/vm/mem_profiling_compressed"),
        },
        "swap_devices": Path("/proc/swaps").read_text().splitlines()[1:],
        "meminfo_kib": m,
        "effective_used_mib": round(actual / 1024, 2),
        "non_cache_residual_mib": round(residual / 1024, 2),
        "estimated_reserve_mib": round(reserve / 1024, 2),
        "estimated_low_watermarks_mib": round(low / 1024, 2),
        "reconstruction_error_mib": round((actual - reconstructed) / 1024, 2),
        "pressure": pressure,
        "pss_unavailable_or_exited": unavailable,
        "pss_scope": "readable processes only; not whole-system RAM",
        "processes": sorted(rows, key=lambda x: x["pss_kib"], reverse=True),
        "capture_duration_ms": round((time.monotonic_ns() - started) / 1e6, 2),
    }


def main():
    print(json.dumps(snapshot(), indent=2))


if __name__ == "__main__":
    main()
