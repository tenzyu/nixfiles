#!/usr/bin/env python3
"""Git-only, deterministic proposal of possibly stale OKF concepts.

A changed dependency means REVIEW NEEDED, not that a factual claim is false.
No LLM execution, network access, PR-state inference or host access.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

def git(root, *args):
    return subprocess.run(["git", *args], cwd=root, capture_output=True,
                          text=True, check=False)

def inspect(root, manifest):
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        raise ValueError("unsupported provenance schema")
    baseline = data["reviewed_revision"]
    if len(baseline) != 40 or git(root, "cat-file", "-e", baseline + "^{commit}").returncode:
        raise ValueError("missing immutable reviewed commit " + baseline)
    results, names = [], set()
    for row in data["pages"]:
        page, sources = row["page"], row["sources"]
        if page in names or not sources:
            raise ValueError("duplicate page or missing sources: " + page)
        names.add(page)
        if not (root / page).is_file():
            raise ValueError("missing page: " + page)
        for path in sources:
            if path.startswith("/") or ".." in Path(path).parts or not (root / path).is_file():
                raise ValueError("missing/unsafe source path: " + path)
        rev = row.get("reviewed_revision", baseline)
        if git(root, "cat-file", "-e", rev + "^{commit}").returncode:
            raise ValueError("unavailable review commit " + rev)
        blobs = row.get("source_blobs", {})
        if any(path not in sources for path in blobs):
            raise ValueError("source_blobs refers to untracked dependency: " + page)
        changed = []
        by_revision = [path for path in sources if path not in blobs]
        if by_revision:
            proc = git(root, "diff", "--name-only", rev, "HEAD", "--", *by_revision)
            if proc.returncode:
                raise ValueError("git diff failed for " + page + ": " + proc.stderr)
            changed.extend(proc.stdout.splitlines())
        for path, digest in blobs.items():
            if len(digest) != 40 or any(c not in "0123456789abcdef" for c in digest):
                raise ValueError("invalid blob identity: " + path)
            actual = git(root, "hash-object", "--", path)
            if actual.returncode:
                raise ValueError("unable to hash " + path + ": " + actual.stderr)
            if actual.stdout.strip() != digest:
                changed.append(path)
        changed = sorted(set(changed))
        results.append({"page": page, "reviewed_revision": rev,
                        "changed_sources": changed, "status": "REVIEW" if changed else "CURRENT"})
    return results

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument("--manifest", type=Path)
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--strict", action="store_true", help="block if any dependency changed")
    args = ap.parse_args()
    root = args.root.resolve()
    path = args.manifest or root / "docs/memory/provenance.json"
    try:
        results = inspect(root, path)
    except (ValueError, KeyError, OSError) as exc:
        print("ERROR provenance:", exc, file=sys.stderr)
        return 2
    for item in results:
        if item["status"] == "REVIEW" or not args.summary:
            print(json.dumps(item, ensure_ascii=False))
    stale = sum(item["status"] == "REVIEW" for item in results)
    print(f"wiki scan: {len(results)} pages; {stale} candidates for source review")
    return 3 if stale and args.strict else 0

if __name__ == "__main__":
    sys.exit(main())
