"""Audit exact attempt-one receipts without re-rendering untrusted logs."""
import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

RUN = 45950924956
REPLAY = "c89f856a0608a10f3eec6bc9a70812b2ac1e44d3"
REPO = os.environ["GITHUB_REPOSITORY"]
ARM, STAGE = sys.argv[1:3]
ROOT = Path(os.environ["RUNNER_TEMP"]) / "historical-audit"
ROOT.mkdir()
def require(ok, why):
    if not ok:
        raise RuntimeError(why)
def api(path,*options):
    return subprocess.check_output(["gh","api",*options,path],timeout=180)
def git(*args,env=None):
    return subprocess.check_output(["git",*args],env=env,text=True).strip()

raw = (Path(os.environ["RUNNER_TEMP"])/"historical-fixtures"/"fixtures.json").read_bytes()
require(hashlib.sha256(raw).hexdigest()=="ffce9f4e51ede20578b2e60ce95f643ffbee0848e7f350f58c0964a98aa3ee9c","fixture digest mismatch")
fixtures={r["pr"]:r for r in json.loads(raw)["receipts"] if r["stage"]==STAGE}
require(len(fixtures)==10,"fixture census")
meta=json.loads(api(f"repos/{REPO}/actions/runs/{RUN}"))
require(meta["head_sha"]==REPLAY,"run identity")
pages=json.loads(api(f"repos/{REPO}/actions/runs/{RUN}/attempts/1/jobs?per_page=100","--paginate","--slurp"))
all_jobs=[j for p in pages for j in p["jobs"]]
require(len(all_jobs)==len({j["id"] for j in all_jobs})==561,"unexpected attempt-one census")
name=re.compile(r"^(baseline|candidate)-(head|merge)-(?:compute-host|nix-validation) \((\d+)\) / (.+)$")
jobs=[]
for job in all_jobs:
    if job["name"]=="prepare":
        continue
    m=name.fullmatch(job["name"])
    require(m is not None,"unrecognized job label: "+job["name"])
    if m.group(1,2)==(ARM,STAGE):
        jobs.append((job,int(m.group(3)),m.group(4)))
require(len(jobs)==140,"phase census")
ordinary={
"Home Manager migration and recovery","Nix evaluation and focused regression tests",
"Tailnet-only ingress negative controls","Platform multi-machine-lab",
"Build neko7-splitcast-runtime deployment artifact","Incus container lifecycle",
"Independent workload deployment and rollback",
"Discover independent image outputs and validate operator menu","Platform platform-services",
"Build neko7-t3-runtime deployment artifact","Build neko7-minecraft-system deployment artifact",
"Build immich image","Build syncthing image"}
on_demand="On-demand signed SplitCast cache verification"
pattern=re.compile(rb"^\d{4}-\d\d-\d\dT\S+ HISTORICAL_RECEIPT arm=(baseline|candidate) stage=(head|merge) pr=(\d+) original=([a-f0-9]{40}) original_tree=([a-f0-9]{40}) commit=([a-f0-9]{40}) tree=([a-f0-9]{40}) lock=([a-f0-9]{64})\r?$",re.M)
def inspect(item):
    job,pr,gate=item
    receipt={"job":job["id"],"pr":pr,"gate":gate,"conclusion":job["conclusion"]}
    if gate==on_demand:
        require(job["conclusion"]=="skipped","on-demand gate unexpectedly ran")
        return receipt
    require(gate in ordinary and job["conclusion"] in {"success","failure"},"invalid ordinary gate")
    rows=pattern.findall(api(f"repos/{REPO}/actions/jobs/{job['id']}/logs","--allow-escape-sequences"))
    require(len(rows)==1,"receipt census: "+str(len(rows)))
    arm,stage,n,original,ot,commit,t,lock=(x.decode() for x in rows[0])
    f=fixtures[pr]
    require((arm,stage,int(n),original,ot,t,lock)==(ARM,STAGE,pr,f["originalCommit"],f["originalTree"],f[ARM+"Tree"],f["lock"]),"fixture mismatch")
    # Reconstruct the exact Git commit object independently, even if replay worktree
    # commits were never pushed. SHA1 is the native Git object identity here.
    payload=(f"tree {t}\nparent {original}\nauthor CI replay <ci-replay@example.invalid> 1795737600 +0000\ncommitter CI replay <ci-replay@example.invalid> 1795737600 +0000\n\ntest(ci): replay historical PR {pr} {stage} {arm}\n").encode()
    expected=hashlib.sha1(f"commit {len(payload)}\0".encode()+payload).hexdigest()
    require(commit==expected,"effective commit mismatch")
    steps=job.get("steps",[])
    if ARM=="candidate" and gate=="Nix evaluation and focused regression tests":
        matches=[s for s in steps if s["name"]=="Verify materialized theme source provenance"]
        require(len(matches)==1 and matches[0]["conclusion"]=="success","missing provenance execution")
        receipt["provenanceSeconds"]=(__import__("datetime").datetime.fromisoformat(matches[0]["completed_at"].replace("Z","+00:00"))-__import__("datetime").datetime.fromisoformat(matches[0]["started_at"].replace("Z","+00:00"))).total_seconds()
    receipt.update({"original":original,"tree":t,"commit":commit,"lock":lock})
    return receipt
receipts,errors=[],[]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    futures={pool.submit(inspect,j):j[0]["id"] for j in jobs}
    for f in concurrent.futures.as_completed(futures):
        try:
            receipts.append(f.result())
        except Exception as e:
            errors.append({"job":futures[f],"error":str(e)})
groups=defaultdict(list)
for r in receipts:
    groups[r["pr"]].append(r)
for pr in fixtures:
    rs=groups[pr]
    if len(rs)!=14 or {r["gate"] for r in rs}!=ordinary|{on_demand} or len({r["commit"] for r in rs if r["gate"]!=on_demand})!=1:
        errors.append({"pr":pr,"error":"gate or commit census mismatch"})
report={"run":RUN,"attempt":1,"arm":ARM,"stage":STAGE,"counts":dict(Counter(r["conclusion"] for r in receipts)),"receipts":sorted(receipts,key=lambda r:(r["pr"],r["gate"])),"errors":errors}
(ROOT/"audit.json").write_text(json.dumps(report,indent=2)+"\n")
print("HISTORICAL_AUDIT",ARM,STAGE,len(receipts),len(errors),report["counts"])
require(not errors and len(receipts)==140,"identity audit failed")
