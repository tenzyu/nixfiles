#!/usr/bin/env python3
"""Independent stock-OBS WebSocket firewall acceptance probes; never changes rules."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import socket
import subprocess
import sys

PORT = 4455
TABLE = "splitcast-obs-websocket-guard"


def probe(host: str, timeout: float = 2) -> tuple[bool, str]:
    try:
        with socket.create_connection((host, PORT), timeout=timeout):
            return True, "tcp_connect_succeeded"
    except (OSError, TimeoutError) as exc:
        return False, f"tcp_connect_failed:{type(exc).__name__}"


def nft_guard_present(output: str) -> bool:
    """Require exact declarative guard shape, not arbitrary counters or firewall trust."""
    import re
    text = " ".join(output.split())
    return (
        f"table inet {TABLE}" in text
        and "type filter hook input priority" in text
        and re.search(r'iifname != "?lo"? tcp dport 4455 .*\bdrop\b', text) is not None
    )


def read_guard() -> tuple[bool, str]:
    try:
        p = subprocess.run(["nft", "list", "table", "inet", TABLE],
                           capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"nft_unavailable:{type(exc).__name__}"
    if p.returncode != 0:
        return False, "nft_not_readable_or_missing"
    return nft_guard_present(p.stdout), "nft_rule_inspection"


def run_local() -> dict:
    reachable, detail = probe("127.0.0.1")
    guard, guard_detail = read_guard()
    return {
        "kind": "local", "host": socket.gethostname(), "listener_local": reachable,
        "listener_result": detail, "nft_guard_found": guard,
        "nft_result": guard_detail, "ready": reachable and guard,
    }


def run_remote(host: str) -> dict:
    if host in ("", "localhost", "127.0.0.1", "::1"):
        raise ValueError("Remote probe requires the actual remote host, not localhost")
    reachable, detail = probe(host)
    return {"kind": "remote", "target_host": host, "external_tcp_connected": reachable,
            "result": detail, "no_remote_connection_observed": not reachable,
            "warning": "A refused/timeout probe alone does not prove firewall security or that OBS was running."}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", choices=("local", "remote"))
    ap.add_argument("--host", default="")
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args(argv)
    if args.mode == "remote" and not args.host:
        ap.error("remote mode needs --host")
    try:
        record = run_local() if args.mode == "local" else run_remote(args.host)
    except ValueError as exc:
        ap.error(str(exc))
    record["observed_utc"] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf8")
    print(json.dumps(record))
    # A remote negative is only INCONCLUSIVE until a separate local-positive
    # and all expected ingress paths are verified by an operator.
    return 0 if args.mode == "local" and record["ready"] else 2


if __name__ == "__main__":
    sys.exit(main())
