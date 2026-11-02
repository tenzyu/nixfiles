#!/usr/bin/env python3
"""Run unit/negative controls and a real read-only collector smoke. Not a benchmark."""

import argparse
from datetime import datetime, timezone
import io
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import unittest

import perf
from test_perf import matrix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    stream = io.StringIO()
    suite = unittest.defaultTestLoader.discover(str(root), pattern="test_*.py")
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    print(stream.getvalue(), end="")
    report = {"schema": 1, "kind": "instrument_verification_not_performance",
              "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
              "base_revision": "3cf330792d31df0721289d91e5643aa5fdee8f77",
              "source_sha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(root.glob("*.py"))},
              "tests_run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
              "status": "PASS" if result.wasSuccessful() else "FAIL",
              "unit_test_output": stream.getvalue().splitlines(),
              "command": "python3 scripts/splitcast/verify.py --output scripts/splitcast/evidence/verification.json"}
    with tempfile.TemporaryDirectory(prefix="splitcast-instrument-") as temp:
        directory = Path(temp)
        positive = matrix()
        for sample in positive[-1]["samples"][1:]:
            sample["ticks"] = 120
        positive[-1]["frames"]["p99_ms"] = 12
        paths = []
        for index, run in enumerate(positive):
            path = directory / f"positive-{index}.json"
            perf.save(path, run)
            paths.append(str(path))
        completed = subprocess.run([sys.executable, str(root / "perf.py"), "compare", *paths,
                                    "--output", str(directory / "positive.json")], capture_output=True, text=True, timeout=10)
        comparison = perf.load(directory / "positive.json")
        report["generated_fixture_cli_control"] = {
            "kind": "generated control, not observed performance", "exit_code": completed.returncode,
            "status": comparison["status"], "expected_cpu_delta_one_core_percent": -80,
            "actual_cpu_delta_one_core_percent": comparison.get("new_minus_baseline", {}).get("splitcast", {}).get("process_one_core_percent"),
            "expected_p99_delta_ms": 2,
            "actual_p99_delta_ms": comparison.get("new_minus_baseline", {}).get("splitcast", {}).get("p99_ms"),
        }
        control = report["generated_fixture_cli_control"]
        if completed.returncode != 0 or control["actual_cpu_delta_one_core_percent"] != -80 or control["actual_p99_delta_ms"] != 2:
            report["status"] = "FAIL"
        fixture = matrix()[0]["conditions"]
        fixture["common"].update(cpu_count=os.cpu_count(), kernel=platform.release(), hardware_id="instrument_smoke_only")
        perf.save(directory / "conditions.json", fixture)
        command = [sys.executable, str(root / "perf.py"), "collect", "--conditions", str(directory / "conditions.json"),
                   "--series", "baseline", "--condition", "game_only", "--revision", "instrument-only",
                   "--pid", str(os.getpid()), "--duration", "2", "--interval", "0.2", "--instrument-smoke",
                   "--output", str(directory / "smoke.json")]
        completed = subprocess.run(command, capture_output=True, text=True, timeout=30)
        if completed.returncode != 0:
            report["status"] = "FAIL"
            report["collector_error"] = completed.stdout + completed.stderr
        else:
            smoke = perf.load(directory / "smoke.json")
            report["collector_smoke"] = {"duration_s": smoke["duration_s"], "samples": len(smoke["samples"]),
                                         "errors": smoke["errors"], "instrument_smoke": smoke["instrument_smoke"],
                                         "route_dump_status": smoke["route_dump"]["status"],
                                         "collector_versions": smoke["collector_versions"]}
            if smoke["errors"]:
                report["status"] = "FAIL"
            runs = matrix()
            # Exercise the actual CLI refusal path using an observed short run.
            runs[0] = smoke
            paths = []
            for index, run in enumerate(runs):
                path = directory / f"run-{index}.json"
                perf.save(path, run)
                paths.append(str(path))
            compared = subprocess.run([sys.executable, str(root / "perf.py"), "compare", *paths,
                                       "--output", str(directory / "refused.json")], capture_output=True, text=True, timeout=10)
            refusal = perf.load(directory / "refused.json")
            report["short_run_cli_control"] = {"exit_code": compared.returncode, **refusal}
            if compared.returncode != 2 or refusal["status"] != "REFUSED" or "smoke" not in refusal["reason"]:
                report["status"] = "FAIL"
    perf.save(args.output, report)
    print(json.dumps({"status": report["status"], "tests_run": report["tests_run"], "output": args.output}))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
