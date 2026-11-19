#!/usr/bin/env python3
"""Source-route smoke test and descriptive lexical retrieval comparison.

Not an LLM answer benchmark. Evaluator fixtures are outside the agent Wiki.
"""
import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

STOP = {"the", "and", "that", "then", "this", "with", "from", "which",
        "what", "when", "where", "should", "could", "does", "there", "would"}
def load(root, fixture):
    cases = json.loads(fixture.read_text(encoding="utf-8"))["cases"]
    if len(cases) < 8:
        raise ValueError("too few independent questions")
    ids = set()
    index = (root / "docs/memory/index.md").read_text(encoding="utf-8")
    for case in cases:
        if case["id"] in ids:
            raise ValueError("duplicate question " + case["id"])
        ids.add(case["id"])
        route = root / case["route"]
        source = root / case["source"]
        if not route.is_file() or not source.is_file():
            raise ValueError("broken expected route/source: " + case["id"])
        if route.name not in index:
            raise ValueError("unindexed expected route: " + case["route"])
        if not case["question"].strip() or not case["criteria"]:
            raise ValueError("missing question/criteria: " + case["id"])
    return cases

def documents(root):
    raw, wiki = {}, {}
    for dirname in ("modules", "lib", "docs/cookbook"):
        for file in (root / dirname).rglob("*"):
            if file.is_file() and file.suffix in (".nix", ".md", ".py"):
                raw[file.relative_to(root).as_posix()] = file.read_text(encoding="utf-8", errors="replace")
    raw["README.md"] = (root / "README.md").read_text(encoding="utf-8")
    for file in (root / "docs/memory").glob("*.md"):
        wiki[file.relative_to(root).as_posix()] = file.read_text(encoding="utf-8")
    wiki["MEMORY.md"] = (root / "MEMORY.md").read_text(encoding="utf-8")
    return raw, wiki

def ranks(raw, wiki, cases, limit):
    con = sqlite3.connect(":memory:")
    con.execute("CREATE VIRTUAL TABLE corpus USING fts5(path UNINDEXED, scope UNINDEXED, body)")
    con.executemany("INSERT INTO corpus VALUES (?, ?, ?)",
                    [(name, "raw", body) for name, body in raw.items()] +
                    [(name, "wiki", body) for name, body in wiki.items()])
    scores = {"search_only": 0, "wiki_and_search": 0}
    rows = []
    for case in cases:
        tokens = [t for t in re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{2,}", case["question"].lower())
                  if t not in STOP]
        query = " OR ".join('"' + t.replace('"', '') + '"' for t in dict.fromkeys(tokens))
        current = {"id": case["id"]}
        for arm, where in (("search_only", "scope='raw'"),
                           ("wiki_and_search", "scope IN ('raw', 'wiki')")):
            hits = [r[0] for r in con.execute(
                "SELECT path FROM corpus WHERE corpus MATCH ? AND " + where +
                " ORDER BY bm25(corpus) LIMIT ?", (query, limit)).fetchall()]
            expect = case["source"] if arm == "search_only" else case["route"]
            passed = expect in hits
            scores[arm] += int(passed)
            current[arm] = {"expected_path_retrieved": passed, "top_paths": hits}
        rows.append(current)
    return {"method": "lexical FTS5 path recall only; NOT factual accuracy",
            "questions": len(cases), "k": limit, "route_hits": scores, "per_question": rows}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument("--fixture", type=Path)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--smoke", action="store_true")
    mode.add_argument("--rank", action="store_true")
    ap.add_argument("--k", type=int, default=8)
    args = ap.parse_args()
    root = args.root.resolve()
    try:
        cases = load(root, args.fixture or root / "scripts/ci/fixtures/retrieval-cases.json")
        if args.rank:
            if args.k < 1:
                raise ValueError("k must be positive")
            raw, wiki = documents(root)
            print(json.dumps(ranks(raw, wiki, cases, args.k), indent=2))
        else:
            print(f"retrieval route smoke: {len(cases)} questions, indexed Wiki routes and primary sources present")
    except (ValueError, KeyError, OSError, sqlite3.Error) as exc:
        print("ERROR retrieval:", exc, file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(main())
