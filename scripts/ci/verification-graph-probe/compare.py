"""Compare Nix evaluator observations, never authorize test skipping."""
import json
import re
import sys
from pathlib import Path

DRV = re.compile(r"/nix/store/[0-9a-z]{32}-[^/]+\.drv")


def snapshot(names, rows):
    if not isinstance(names, list) or not all(isinstance(n, str) for n in names):
        raise ValueError("invalid check catalog")
    if len(set(names)) != len(names):
        raise ValueError("duplicate check catalog entry")
    result = dict.fromkeys(names)
    seen = set()
    for row in rows:
        path = row.get("attrPath")
        if not isinstance(path, list) or len(path) != 1 or not isinstance(path[0], str):
            raise ValueError("unexpected evaluator attribute path")
        name = path[0]
        if name not in result or name in seen:
            raise ValueError("unexpected or duplicate evaluator result: " + name)
        seen.add(name)
        drv = row.get("drvPath")
        if not row.get("error") and isinstance(drv, str) and DRV.fullmatch(drv):
            result[name] = drv
    return result


def compare(base, candidate):
    result = {}
    for name in sorted(base.keys() | candidate.keys()):
        before, after = base.get(name), candidate.get(name)
        if name not in candidate:
            status = "removed"
        elif after is None or (name in base and before is None):
            status = "unknown"
        elif name not in base:
            status = "added"
        elif before == after:
            status = "same-derivation"
        else:
            status = "changed"
        result[name] = {"status": status, "base": before, "candidate": after}
    return result


def load(directory):
    path = Path(directory)
    names = json.loads((path / "checks.json").read_text())
    rows = [json.loads(line) for line in (path / "evaluation.jsonl").read_text().splitlines() if line.strip()]
    return snapshot(names, rows)


if __name__ == "__main__":
    report = compare(load(sys.argv[1]), load(sys.argv[2]))
    print(json.dumps(report, indent=2, sort_keys=True))
    if any(row["status"] in {"unknown", "removed"} for row in report.values()):
        sys.exit(1)
