import hashlib
import json
import os
from pathlib import Path

path = Path(os.environ["RUNNER_TEMP"]) / "historical-fixtures" / "fixtures.json"
data = path.read_bytes()
if hashlib.sha256(data).hexdigest() != "ffce9f4e51ede20578b2e60ce95f643ffbee0848e7f350f58c0964a98aa3ee9c":
    raise RuntimeError("fixture artifact digest changed")
report = json.loads(data)
rows = report["receipts"]
if len(rows) != 20 or {(r["pr"], r["stage"]) for r in rows} != {(i, s) for i in range(102, 112) for s in ("head","merge")}:
    raise RuntimeError("incomplete fixture set")
with open(os.environ["GITHUB_OUTPUT"], "a") as f:
    for stage in ("head","merge"):
        selected = [{k:r[k] for k in ("pr","stage","originalCommit","originalTree","baselineTree","candidateTree","lock")} for r in rows if r["stage"] == stage]
        selected.sort(key=lambda r:r["pr"])
        f.write(stage+"s="+json.dumps(selected,separators=(",",":"))+"\n")
print("HISTORICAL_FIXTURES_VERIFIED",len(rows))
