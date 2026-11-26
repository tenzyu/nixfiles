#!/usr/bin/env python3
"""Matched neko5 resource experiment; native Nix owns builds and boot activation."""
import argparse
import json
import os
import shlex
import statistics
import subprocess
import sys
import time
from pathlib import Path

BASELINE = "291cfbe33a2c920faeaa6b1f76ef8f0a4b208138"
ROOT = Path(__file__).resolve().parents[2]
PHASES = ("vt", "jay-idle", "post-workload")
ARMS = ("baseline", "candidate")
SAMPLES = 5
BOOTS = 3


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def write_new(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def manifest(directory):
    return json.loads((directory / "manifest.json").read_text())


def prepare(directory):
    if command("git", "status", "--porcelain"):
        raise ValueError("Use a clean committed checkout.")
    candidate = command("git", "rev-parse", "HEAD")
    if candidate == BASELINE:
        raise ValueError("Candidate must differ from baseline.")
    directory.mkdir(parents=True, exist_ok=False)
    refs = {}
    for arm, rev in zip(ARMS, (BASELINE, candidate)):
        flake = "git+" + ROOT.as_uri() + "?rev=" + rev
        link = directory / arm
        subprocess.run(["nix", "build", "--out-link", str(link),
                        flake + "#nixosConfigurations.neko5.config.system.build.toplevel"],
                       cwd=ROOT, check=True)
        refs[arm] = {"rev": rev, "flake": flake, "closure": str(link.resolve(strict=True))}
    if refs["baseline"]["closure"] == refs["candidate"]["closure"]:
        raise ValueError("The two system closures are identical.")
    write_new(directory / "manifest.json", refs)
    print_boot(directory)


def print_boot(directory):
    refs = manifest(directory)
    for arm in ARMS:
        print(arm + ": " + refs[arm]["closure"])
        print(shlex.join(["sudo", "nixos-rebuild", "boot", "--flake",
                          refs[arm]["flake"] + "#neko5"]))
    print("Stage only with operator approval, then reboot; never switch during a session.")


def current_identity():
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    current = str(Path("/run/current-system").resolve(strict=True))
    booted = str(Path("/run/booted-system").resolve(strict=True))
    if current != booted:
        raise ValueError("Active and booted generations differ; reboot first.")
    return boot, current


def capture(directory, phase):
    refs = manifest(directory)
    if os.uname().nodename.split(".")[0] != "neko5":
        raise ValueError("Capture must run on physical neko5.")
    boot, closure = current_identity()
    arm = next((a for a in ARMS if refs[a]["closure"] == closure), None)
    if arm is None:
        raise ValueError("Booted closure is not in the manifest.")
    destination = directory / f"{arm}-{boot}-{phase}.json"
    if destination.exists():
        raise ValueError("This boot/phase already has a receipt.")
    # Enforce the order of phases without trying to start or stop the desktop.
    for previous in PHASES[:PHASES.index(phase)]:
        if not (directory / f"{arm}-{boot}-{previous}.json").exists():
            raise ValueError(f"Capture {previous} first on this boot.")
    subprocess.run(["sudo", "-v"], check=True)
    print(f"{arm} / {boot} / {phase}: keep the agreed workload idle for 120 seconds.", flush=True)
    time.sleep(120)
    samples = []
    for index in range(SAMPLES):
        if current_identity() != (boot, closure):
            raise ValueError("Generation changed during capture.")
        sample = json.loads(command("sudo", "-n", sys.executable,
                                    str(ROOT / "scripts/desktop/memory-snapshot.py")))
        identity = sample["identity"]
        if (identity["boot_id"], identity["current_system"], identity["booted_system"]) != (boot, closure, closure):
            raise ValueError("Snapshot identity mismatch.")
        if sample["effective_uid"] != 0:
            raise ValueError("PSS collection requires root.")
        samples.append(sample)
        if index < SAMPLES - 1:
            time.sleep(10)
    write_new(destination, {"arm": arm, "phase": phase, "boot": boot,
                            "closure": closure, "samples": samples})
    print(destination)


def report(directory):
    refs = manifest(directory)
    groups = {arm: {} for arm in ARMS}
    for path in sorted(directory.glob("*.json")):
        if path.name == "manifest.json":
            continue
        receipt = json.loads(path.read_text())
        arm, phase, boot = (receipt[k] for k in ("arm", "phase", "boot"))
        samples = receipt["samples"]
        if arm not in ARMS or phase not in PHASES or len(samples) != SAMPLES:
            raise ValueError(f"Invalid receipt: {path}")
        if receipt["closure"] != refs[arm]["closure"]:
            raise ValueError(f"Wrong closure: {path}")
        for sample in samples:
            identity = sample["identity"]
            if (identity["boot_id"], identity["current_system"], identity["booted_system"]) != (boot, refs[arm]["closure"], refs[arm]["closure"]):
                raise ValueError(f"Wrong boot or generation: {path}")
        phases = groups[arm].setdefault(boot, {})
        if phase in phases:
            raise ValueError(f"Duplicate boot/phase: {path}")
        phases[phase] = samples
    if set(groups["baseline"]) & set(groups["candidate"]):
        raise ValueError("Boot IDs overlap across arms.")
    complete = all(len(groups[arm]) >= BOOTS and
                   all(set(phases) == set(PHASES) for phases in groups[arm].values())
                   for arm in ARMS)
    print("Phase | Arm | independent boots | median MiB | range MiB | median readable PSS MiB")
    results = {}
    for phase in PHASES:
        for arm in ARMS:
            batches = [p[phase] for p in groups[arm].values() if phase in p]
            if not batches:
                continue
            medians = [statistics.median((s["meminfo_kib"]["MemTotal"] - s["meminfo_kib"]["MemAvailable"]) / 1024 for s in batch) for batch in batches]
            pss = [statistics.median(sum(p["pss_kib"] for p in s["processes"]) / 1024 for s in batch) for batch in batches]
            results[arm, phase] = statistics.median(medians)
            print(f"{phase} | {arm} | {len(batches)} | {statistics.median(medians):.2f} | {min(medians):.2f}..{max(medians):.2f} | {statistics.median(pss):.2f}")
        if all((a, phase) in results for a in ARMS):
            print(f"  candidate - baseline: {results['candidate', phase] - results['baseline', phase]:+.2f} MiB")
    print("COMPLETE memory receipts" if complete else "INCOMPLETE: need >=3 full independent boots per arm.")
    print("Raw swap, VM counters, PSI and PSS coverage remain in each receipt. Review separately.")
    print("No automatic acceptance: verify physical GPU/audio/SSH/input and matched workload conditions.")
    return 0 if complete else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=lambda p: Path(p).expanduser().resolve())
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("prepare")
    sub.add_parser("boot-commands")
    capture_parser = sub.add_parser("capture")
    capture_parser.add_argument("phase", choices=PHASES)
    sub.add_parser("report")
    args = parser.parse_args()
    try:
        if args.action == "prepare":
            prepare(args.directory)
        elif args.action == "boot-commands":
            print_boot(args.directory)
        elif args.action == "capture":
            capture(args.directory, args.phase)
        else:
            return report(args.directory)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"memory-ab: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
