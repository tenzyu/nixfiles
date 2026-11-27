"""Diagnostic-only comparison of realized validation link farms."""
import json
import os
import sys
from pathlib import Path


def members(root):
    result = {}
    for entry in root.iterdir():
        if not entry.is_symlink() or not entry.exists():
            raise ValueError(f"invalid validation member: {entry}")
        result[entry.name] = os.readlink(entry)
    return result


def verify(base_names, candidate_names, base, candidate):
    if len(base_names) != len(set(base_names)) or len(candidate_names) != len(set(candidate_names)):
        raise ValueError("duplicate public checks")
    if set(base_names) != set(candidate_names):
        raise ValueError("public check catalog changed")
    if not base or base.keys() != candidate.keys():
        raise ValueError("aggregate membership changed")
    changed = sorted(name for name in base if base[name] != candidate[name])
    if set(changed) - {"docs"}:
        raise ValueError("unexpected leaf output change: " + str(changed))
    return {"public_checks": len(base_names), "aggregate_members": sorted(base),
            "changed_leaf_outputs": changed, "baseline": base, "candidate": candidate}


if __name__ == "__main__":
    root = Path(sys.argv[1])
    names = [json.loads((root / f"{label}.checks.json").read_text()) for label in ("baseline", "candidate")]
    links = [members(root / f"{label}.validation") for label in ("baseline", "candidate")]
    print(json.dumps(verify(*names, *links), indent=2, sort_keys=True))
