"""Historical fixture only: let Nix schedule the union of two root DAGs."""
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

def command(*args, cwd=None, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def prepare(root, spec, fixture, patch):
    worktree = root / str(fixture["pr"])
    command("git", "worktree", "add", "--detach", str(worktree), fixture["rev"])
    require(command("git", "rev-parse", "HEAD^{tree}", cwd=worktree) == fixture["originalTree"], "original tree mismatch")
    command("git", "apply", "--index", "--check", str(patch), cwd=worktree)
    command("git", "apply", "--index", str(patch), cwd=worktree)
    tree = command("git", "write-tree", cwd=worktree)
    require(tree == fixture["tree"], "effective tree mismatch")
    env = dict(os.environ)
    for role in ("AUTHOR", "COMMITTER"):
        env["GIT_" + role + "_NAME"] = "CI replay"
        env["GIT_" + role + "_EMAIL"] = "ci-replay@example.invalid"
        env["GIT_" + role + "_DATE"] = "2026-11-27T00:00:00Z"
    effective = command("git", "commit-tree", tree, "-p", fixture["rev"], "-m",
                        "fix(safety-shell): apply verified lock lifetime repair to replay fixture",
                        cwd=worktree, env=env)
    require(effective == fixture["effectiveCommit"], "effective commit mismatch")
    command("git", "checkout", "--force", "--detach", effective, cwd=worktree)
    require(not command("git", "status", "--porcelain", cwd=worktree), "dirty fixture")
    require(hashlib.sha256((worktree / "flake.lock").read_bytes()).hexdigest() == fixture["lock"], "lock mismatch")
    return str(worktree) + "#checks.x86_64-linux.validation"

def build(installables):
    return json.loads(command("nix", "build", "-L", "--keep-going", "--no-link", "--json", *installables))

def verify_results(results, fixtures):
    actual = {(r["drvPath"], r["outputs"]["out"]) for r in results}
    expected = {(f["drv"], f["output"]) for f in fixtures}
    require(actual == expected, "realized derivation/output set mismatch")
    receipts = []
    for fixture in fixtures:
        output = fixture["output"]
        info = json.loads(command("nix", "path-info", "--json", output))[output]
        require(info["deriver"] == fixture["drv"], "deriver mismatch")
        require(info["narHash"] == fixture["narHash"], "NAR hash mismatch")
        receipts.append({"pr": fixture["pr"], "tree": fixture["tree"], "lock": fixture["lock"],
                         "drv": info["deriver"], "output": output, "narHash": info["narHash"]})
    return receipts

def main():
    arm, index = sys.argv[1], int(sys.argv[2])
    require(arm in ("sequential", "union"), "unknown arm")
    spec = json.loads(Path(__file__).with_name("fixtures.json").read_text())
    fixtures = spec["pairs"][index]
    root = Path(os.environ["RUNNER_TEMP"]) / "native-union"
    root.mkdir()
    require("require-sigs = true" in command("nix", "config", "show").splitlines(), "signature policy changed")
    patch = root / "lock-fix.patch"
    patch.write_bytes(subprocess.check_output(["git", "diff", "--binary", spec["repairBase"], spec["repairHead"], "--", *spec["repairPaths"]]))
    require(patch.stat().st_size > 0, "empty patch")
    targets = [prepare(root, spec, f, patch) for f in fixtures]
    batches = [[i] for i in range(len(targets))] if arm == "sequential" else [list(range(len(targets)))]
    start = time.monotonic()
    receipts = []
    for batch in batches:
        results = build([targets[i] for i in batch])
        verified = verify_results(results, [fixtures[i] for i in batch])
        elapsed = time.monotonic() - start
        receipts.extend({**r, "completionSeconds": elapsed} for r in verified)
    report = {"arm": arm, "pair": index, "sourceRun": spec["sourceRun"], "elapsedSeconds": time.monotonic() - start,
              "receipts": receipts}
    (root / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    for f in fixtures:
        require(not command("git", "status", "--porcelain", cwd=root / str(f["pr"])), "fixture changed")

if __name__ == "__main__":
    main()
