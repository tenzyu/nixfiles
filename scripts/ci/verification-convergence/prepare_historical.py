"""Build exact historical replay fixture trees, without running or merging a PR."""
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

spec=json.loads(Path(__file__).with_name("historical-fixtures.json").read_text())
root=Path(os.environ["RUNNER_TEMP"])/"historical-fixtures"
root.mkdir()
def cmd(*args,cwd=None,env=None):
    return subprocess.check_output(args,cwd=cwd,env=env,text=True).strip()
def require(ok,reason):
    if not ok:
        raise RuntimeError(reason)
def digest(data):
    return hashlib.sha256(data).hexdigest()
def patch(name, before, after, paths):
    p=root/(name+".patch")
    p.write_bytes(subprocess.check_output(["git","diff","--binary",before,after,"--",*paths]))
    require(p.stat().st_size>0,"empty "+name)
    return p
repair=patch("repair",spec["repairBase"],spec["repairHead"],spec["repairPaths"])
materialization=patch("materialization",spec["base"],spec["candidate"],spec["materializationPaths"])
history_parent=spec["historyBase"]
receipts=[]
for row in spec["historical"]:
    parents=cmd("git","rev-list","--parents","-n","1",row["merge"]).split()
    require(parents==[row["merge"],history_parent,row["head"]],f"PR {row['pr']} merge ancestry mismatch")
    require(cmd("git","rev-parse",row["merge"]+"^{tree}")==row["mergeTree"],"historical merge tree mismatch")
    history_parent=row["merge"]
    for stage in ("head","merge"):
        ref=row[stage]
        path=root/f"pr-{row['pr']}-{stage}"
        cmd("git","worktree","add","--detach",str(path),ref)
        try:
            original=cmd("git","rev-parse","HEAD^{tree}",cwd=path)
            lock=digest((path/"flake.lock").read_bytes())
            cmd("git","apply","--index","--check",str(repair),cwd=path)
            cmd("git","apply","--index",str(repair),cwd=path)
            baseline=cmd("git","write-tree",cwd=path)
            cmd("git","apply","--index","--check",str(materialization),cwd=path)
            cmd("git","apply","--index",str(materialization),cwd=path)
            candidate=cmd("git","write-tree",cwd=path)
            require(digest((path/"flake.lock").read_bytes())==lock,"replay lock changed")
            paths=cmd("git","diff","--name-only",baseline,candidate,cwd=path).splitlines()
            require(bool(paths) and all(p=="modules/50-features/desktop/catppuccin.nix" or p.startswith("assets/catppuccin-materialized/") for p in paths),"unexpected materialization scope")
            receipts.append({"pr":row["pr"],"stage":stage,"originalCommit":ref,"originalTree":original,"baselineTree":baseline,"candidateTree":candidate,"lock":lock,"changedPaths":paths})
        finally:
            cmd("git","worktree","remove","--force",str(path))
require(len(receipts)==20,"incomplete fixture set")
report={"repairSha256":digest(repair.read_bytes()),"materializationSha256":digest(materialization.read_bytes()),"receipts":receipts,"sourceGateExecution":"not executed"}
(root/"fixtures.json").write_text(json.dumps(report,indent=2)+"\n")
print("HISTORICAL_FIXTURES",len(receipts))
