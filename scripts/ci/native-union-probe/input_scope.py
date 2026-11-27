"""Compare actual Nix identities and positive/negative input controls."""
import json
import os
import subprocess
import sys
from pathlib import Path

BASE, CANDIDATE = sys.argv[1:3]
ROOT = Path(os.environ["RUNNER_TEMP"]) / "input-scope"
ROOT.mkdir()

def cmd(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()

def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)

def worktree(label, rev):
    p = ROOT / label
    cmd("git", "worktree", "add", "--detach", str(p), rev)
    return p

def identities(p, system, include_host=False):
    targets = {n: f".#checks.{system}.{n}.drvPath" for n in ("clipboard", "memory-snapshot", "desktop-packages")}
    if include_host:
        targets["host"] = ".#nixosConfigurations.neko5.config.system.build.toplevel.drvPath"
    return {n: cmd("nix", "eval", "--raw", "--no-write-lock-file", ref, cwd=p) for n, ref in targets.items()}

def mutate(p, path, system):
    with (p / path).open("a") as f:
        f.write("\n# diagnostic input identity control\n")
    cmd("git", "add", path, cwd=p)
    try:
        return identities(p, system)
    finally:
        cmd("git", "reset", "--hard", "HEAD", cwd=p)

before, after = worktree("baseline", BASE), worktree("candidate", CANDIDATE)
renames = [row.split("\t") for row in cmd("git", "diff", "--name-status", "-M100%", BASE, CANDIDATE).splitlines() if row.startswith("R100\t")]
require(renames, "no exact blob renames detected")
for _, old, new in renames:
    require(cmd("git", "rev-parse", BASE + ":" + old) == cmd("git", "rev-parse", CANDIDATE + ":" + new), "blob changed")
    result = subprocess.run(["git", "grep", "-n", "-F", "--", old], cwd=after, text=True, capture_output=True)
    require(result.returncode == 1, "old path referenced or grep failed: " + old + "\n" + result.stdout + result.stderr)
system = cmd("nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem")
b, a = identities(before, system, True), identities(after, system, True)
memory = mutate(after, "scripts/desktop/memory-snapshot.py", system)
interaction = mutate(after, "scripts/desktop/interaction/cclip-picker.sh", system)
report = {"baseline": b, "candidate": a, "memoryMutation": memory, "interactionMutation": interaction, "renames": renames}
(ROOT / "scope.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
require(a["host"] == b["host"] and a["desktop-packages"] == b["desktop-packages"], "host or packaged-artifact identity changed")
require(a["clipboard"] == memory["clipboard"] and a["memory-snapshot"] != memory["memory-snapshot"], "memory edit invalidation mismatch")
require(a["clipboard"] != interaction["clipboard"] and a["memory-snapshot"] == interaction["memory-snapshot"], "interaction edit invalidation mismatch")
