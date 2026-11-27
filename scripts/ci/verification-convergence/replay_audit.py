"""Audit every executed gate against a reconstructed controlled candidate."""
import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

RUN = 45941774462
REPLAY = "9baf5677f699ca0773b9a1cca4b0d079b67871a6"
REPO = os.environ["GITHUB_REPOSITORY"]
ROOT = Path(os.environ["RUNNER_TEMP"]) / "replay-audit"
ROOT.mkdir()

def require(ok, message):
    if not ok:
        raise RuntimeError(message)

def run(*args, **kw):
    return subprocess.check_output(args, **kw)

def git(*args, env=None):
    return run("git", *args, env=env, text=True).strip()

def api(path, *options):
    return run("gh", "api", *options, path, timeout=180)

spec = json.loads(git("show", REPLAY+":scripts/ci/verification-convergence/burst-fixtures.json"))
meta = json.loads(api(f"repos/{REPO}/actions/runs/{RUN}"))
require(meta["head_sha"] == REPLAY and meta["status"] == "completed" and meta["conclusion"] == "success", "run mismatch")
pages = json.loads(api(f"repos/{REPO}/actions/runs/{RUN}/jobs?per_page=100", "--paginate", "--slurp"))
jobs = [j for p in pages for j in p["jobs"]]
require(len(jobs) == len({j["id"] for j in jobs}) == pages[0]["total_count"] == 280, "job census mismatch")
expected = {}
for arm in ("baseline", "candidate"):
    ref = spec[arm]
    for fixture in spec["fixtures"]:
        fid, path = fixture["id"], fixture[arm]
        old = run("git", "show", f"{ref}:{path}")
        addition = (f"\n<!-- controlled CI replay {fid} -->\n" if path.endswith(".md") else f"\n# controlled CI replay {fid}\n").encode()
        blob = run("git", "hash-object", "-w", "--stdin", input=old+addition).decode().strip()
        original = git("rev-parse", f"{ref}:{path}")
        mode = git("ls-tree", ref, "--", path).split()[0]
        with tempfile.TemporaryDirectory() as td:
            env = dict(os.environ, GIT_INDEX_FILE=str(Path(td)/"index"))
            git("read-tree", ref, env=env)
            git("update-index", "--cacheinfo", f"{mode},{blob},{path}", env=env)
            tree = git("write-tree", env=env)
        lock = hashlib.sha256(run("git","show",f"{ref}:flake.lock")).hexdigest()
        expected[(arm,fid)] = dict(tree=tree, original_blob=original, changed_blob=blob, lock=lock)
for fixture in spec["fixtures"]:
    f = fixture["id"]
    for field in ("original_blob","changed_blob","lock"):
        require(expected[("baseline",f)][field] == expected[("candidate",f)][field], "cross-arm fixture mismatch")
pattern = re.compile(rb"^(?:\d{4}-\d\d-\d\dT\S+ )?REPLAY_IDENTITY arm=(baseline|candidate) fixture=([a-z-]+) commit=([0-9a-f]{40}) tree=([0-9a-f]{40}) original_blob=([0-9a-f]{40}) changed_blob=([0-9a-f]{40}) lock=([0-9a-f]{64})\r?$", re.M)
jobname = re.compile(r"^(baseline|candidate)-(?:compute-host|nix-validation) \(([^,]+),.* / (.+)$")
def receipt(job):
    m = jobname.fullmatch(job["name"])
    require(m is not None, "unexpected job name")
    arm, fid, gate = m.groups()
    if job["conclusion"] == "skipped":
        require(gate == "On-demand signed SplitCast cache verification", "required gate skipped")
        return {"arm":arm,"fixture":fid,"gate":gate,"id":job["id"],"skipped":True}
    require(job["conclusion"] == "success", "non-success gate")
    matches = pattern.findall(api(f"repos/{REPO}/actions/jobs/{job['id']}/logs", "--allow-escape-sequences"))
    require(len(matches) == 1, f"missing/duplicate receipt job {job['id']}: {len(matches)}")
    a,f,commit,tree,original,changed,lock = (x.decode() for x in matches[0])
    got = dict(tree=tree,original_blob=original,changed_blob=changed,lock=lock)
    require((a,f)==(arm,fid) and got==expected[(arm,fid)], f"identity mismatch job {job['id']}")
    return {"arm":arm,"fixture":fid,"gate":gate,"id":job["id"],"commit":commit,**got}
receipts, errors = [], []
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    pending = {pool.submit(receipt,j):j for j in jobs}
    for f in concurrent.futures.as_completed(pending):
        try:
            receipts.append(f.result())
        except Exception as e:
            errors.append({"job":pending[f]["id"],"error":str(e)})
groups = defaultdict(list)
for r in receipts:
    groups[(r["arm"],r["fixture"])].append(r)
for key, rs in groups.items():
    active = [r for r in rs if not r.get("skipped")]
    if len(active)!=13 or len(rs)!=14 or len({r["gate"] for r in rs})!=14 or len({r["commit"] for r in active})!=1:
        errors.append({"group":key,"error":"incomplete or inconsistent gate set"})
for fixture in spec["fixtures"]:
    fid = fixture["id"]
    if {r["gate"] for r in groups[("baseline",fid)]}!={r["gate"] for r in groups[("candidate",fid)]}:
        errors.append({"fixture":fid,"error":"gate set differs between arms"})
report = {"run":RUN,"attempt":meta["run_attempt"],"receipt_count":len(receipts),"errors":errors,"receipts":sorted(receipts,key=lambda r:(r["arm"],r["fixture"],r["gate"]))}
(ROOT/"receipt-audit.json").write_text(json.dumps(report,indent=2)+"\n")
print("RECEIPT_AUDIT",len(receipts),len(errors))
require(not errors and len(groups)==20 and len(receipts)==280, "receipt audit failed")
