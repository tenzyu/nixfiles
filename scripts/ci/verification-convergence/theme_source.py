"""Reproduce pinned source outputs; query cache without changing trust policy."""
import base64
import hashlib
import json
import os
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

root = Path(os.environ["RUNNER_TEMP"]) / "theme-source"
root.mkdir()
old = Path(os.environ["RUNNER_TEMP"]) / "theme-data"

def run(*args):
    return subprocess.check_output(args,text=True).strip()

def need(condition, message):
    if not condition:
        raise RuntimeError(message)

need(hashlib.sha256(Path("flake.lock").read_bytes()).hexdigest()==(old/"lock.sha").read_text().strip(),"lock mismatch")
origin = json.loads((old/"origin.json").read_text())
manifest, cache = {}, {}
for name, entries in sorted(origin.items()):
    need(len(entries)==1 and name in ("starship","firefox","palette"),"unexpected producer output")
    expected, info = next(iter(entries.items()))
    expr = "let f = builtins.getFlake (toString ./.); in f.inputs.catppuccin.packages.x86_64-linux."+name+".drvPath"
    drv = run("nix","eval","--impure","--raw","--expr",expr)
    need(drv==info["deriver"],"upstream derivation changed")
    url = "https://catppuccin.cachix.org/"+Path(expected).name.split("-",1)[0]+".narinfo"
    try:
        with urllib.request.urlopen(url,timeout=25) as res:
            fields=dict(line.split(": ",1) for line in res.read(16384).decode().splitlines() if ": " in line)
            cache[name]={"http":res.status,"store_path":fields.get("StorePath"),"nar_hash":fields.get("NarHash"),"signature_present":"Sig" in fields}
    except urllib.error.HTTPError as e:
        cache[name]={"http":e.code}
    except Exception as e:
        cache[name]={"error":str(e)}
    output = run("nix","build","-L","--no-link","--print-out-paths",drv+"^out")
    need(output==expected,"upstream output changed")
    actual = json.loads(run("nix","path-info","--json",output))[output]
    need(actual["narHash"]==info["narHash"] and actual["deriver"]==drv,"independent origin mismatch")
    source = old/"snapshot"/name
    need(run("nix","hash","path",str(source))==actual["narHash"],"downloaded source NAR mismatch")
    built = Path(output)
    need(all(p.is_dir() or (p.is_file() and not p.is_symlink()) for p in built.rglob("*")),"unexpected file type")
    files = {}
    for p in sorted(built.rglob("*")):
        if p.is_file():
            rel=p.relative_to(built).as_posix()
            data=p.read_bytes()
            need((source/rel).read_bytes()==data,"independent source byte mismatch")
            files[rel]=hashlib.sha256(data).hexdigest()
    need(set(files)=={p.relative_to(source).as_posix() for p in source.rglob("*") if p.is_file()},"source set mismatch")
    manifest[name]={"drvPath":drv,"narHash":actual["narHash"],"files":files}
(root/"manifest.json").write_text(json.dumps(manifest,indent=2,sort_keys=True)+"\n")
(root/"cache.json").write_text(json.dumps(cache,indent=2,sort_keys=True)+"\n")
print("SOURCE_CACHE_OBSERVATIONS",json.dumps(cache,sort_keys=True))
for name, info in sorted(manifest.items()):
    for rel,digest in sorted(info["files"].items()):
        encoded=base64.b64encode((old/"snapshot"/name/rel).read_bytes()).decode()
        parts=[encoded[i:i+3000] for i in range(0,len(encoded),3000)] or [""]
        for i,part in enumerate(parts):
            print("SOURCE_EXPORT",json.dumps({"path":name+"/"+rel,"sha256":digest,"part":i,"count":len(parts),"base64":part},separators=(",",":")))
print("SOURCE_MANIFEST",json.dumps(manifest,sort_keys=True,separators=(",",":")))
