#!/usr/bin/env python3
"""Reproduce the tracked source data from the pinned Catppuccin packages."""
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "manifest.json"

def run(*args):
    return subprocess.check_output(args, cwd=ROOT.parents[1], text=True).strip()

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def nar(path):
    return run("nix", "hash", "path", str(path))

def upstream(names):
    names_json = json.dumps(names)
    expr = (
        "let f = builtins.getFlake (toString ./.); "
        "p = f.inputs.catppuccin.packages.x86_64-linux; "
        "names = builtins.fromJSON ''" + names_json + "''; "
        "in builtins.listToAttrs (map (name: { inherit name; value = p.${name}.drvPath; }) names)"
    )
    return json.loads(run("nix", "eval", "--impure", "--json", "--no-write-lock-file", "--expr", expr))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--refresh", action="store_true", help="regenerate source files and manifest")
    p.add_argument("--require-current", action="store_true", help="reject stale entries instead of allowing native fallback")
    args = p.parse_args()
    require("require-sigs = true" in run("nix", "config", "show").splitlines(), "Nix signature verification is required")
    manifest = json.loads(MANIFEST.read_text())
    require(bool(manifest) and all(re.fullmatch(r"[a-z][a-z0-9-]*", name) for name in manifest), "invalid source names")
    require({x.name for x in (ROOT / "data").iterdir()} == set(manifest), "unexpected source directory set")
    drvs = upstream(sorted(manifest))
    with tempfile.TemporaryDirectory(prefix="catppuccin-materialize-") as temp:
        staged = Path(temp)
        result = {}
        for name, receipt in sorted(manifest.items()):
            source = ROOT / "data" / name
            if not args.refresh:
                require(nar(source) == receipt["narHash"], f"{name}: tracked NAR does not match manifest")
            if not args.refresh and drvs[name] != receipt["drvPath"]:
                require(not args.require_current, f"{name}: stale source; run verify.py --refresh")
                print(f"{name}: stale source is unused; native derivation retained")
                continue
            out = Path(run("nix", "build", "-L", "--no-link", "--print-out-paths", drvs[name] + "^out"))
            require(out.is_dir() and all(x.is_dir() or (x.is_file() and not x.is_symlink()) for x in out.rglob("*")), f"{name}: unexpected upstream file type")
            digest = nar(out)
            if args.refresh:
                shutil.copytree(out, staged / name)
                require(nar(staged / name) == digest, f"{name}: materialization changed output")
                result[name] = {"drvPath": drvs[name], "narHash": digest}
            else:
                require(digest == receipt["narHash"], f"{name}: independently realized upstream differs")
                print(f"{name}: pinned derivation and NAR verified")
        if args.refresh:
            # Replace only the owned generated directory after every source is realized.
            shutil.rmtree(ROOT / "data")
            shutil.copytree(staged, ROOT / "data")
            MANIFEST.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
            print("Refresh complete; review upstream licenses and commit data with the manifest.")

if __name__ == "__main__":
    main()
