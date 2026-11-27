"""Compare real candidate identities; reject stale/corrupt materialized source use."""
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

base, candidate = sys.argv[1:3]
root = Path(os.environ["RUNNER_TEMP"]) / "materialized-contract"
root.mkdir()
def run(*args,cwd=None):
    return subprocess.check_output(args,cwd=cwd,text=True).strip()
def require(ok,message):
    if not ok:
        raise RuntimeError(message)
def worktree(name,rev):
    path=root/name
    run("git","worktree","add","--detach",str(path),rev)
    require(run("git","rev-parse","HEAD",cwd=path)==rev,"worktree identity mismatch")
    return path
def eval_json(path,attr,apply,materialized):
    args=["nix","eval","--json","--no-write-lock-file","--option","eval-cache","false"]
    if materialized:
        args+=["--option","allow-import-from-derivation","false"]
    return json.loads(run(*args,attr,"--apply",apply,cwd=path))
left,right=worktree("baseline",base),worktree("candidate",candidate)
reports={}
for name,path in (("baseline",left),("candidate",right)):
    start=time.monotonic()
    roots=eval_json(path,".#nixosConfigurations","hosts: builtins.mapAttrs (_: host: host.config.system.build.toplevel.drvPath) hosts",name=="candidate")
    checks=eval_json(path,".#checks.x86_64-linux","checks: builtins.mapAttrs (_: check: check.drvPath) checks",name=="candidate")
    reports[name]={"commit":run("git","rev-parse","HEAD",cwd=path),"tree":run("git","rev-parse","HEAD^{tree}",cwd=path),"lock":hashlib.sha256((path/"flake.lock").read_bytes()).hexdigest(),"hosts":roots,"checks":checks,"seconds":time.monotonic()-start}
(root/"identities.json").write_text(json.dumps(reports,indent=2)+"\n")
a,b=reports["baseline"],reports["candidate"]
require(a["lock"]==b["lock"] and a["hosts"]==b["hosts"],"host/lock identity mismatch")
require(set(a["checks"])==set(b["checks"]),"check catalog changed")
changed=[n for n in a["checks"] if a["checks"][n]!=b["checks"][n]]
require(not (set(changed)-{"docs","validation"}),f"unexpected check changes {changed}")
print("IDENTITIES",len(a["hosts"]),len(a["checks"]),changed)

asset=right/"assets/catppuccin-materialized"
manifest=asset/"manifest.json"
original=manifest.read_text()
names=sorted(json.loads(original))
prefix="let f = builtins.getFlake (toString ./.); lib = f.inputs.nixpkgs.lib; upstream = f.inputs.catppuccin.packages.x86_64-linux; sources = import ./assets/catppuccin-materialized { inherit lib upstream; }; in "
def source_eval(expr):
    return run("nix","eval","--impure","--json","--option","eval-cache","false","--option","allow-import-from-derivation","false","--expr",prefix+expr,cwd=right)
selection="builtins.listToAttrs (map (name: { inherit name; value = { isDerivation = lib.isDerivation sources.${name}; drvPath = if lib.isDerivation sources.${name} then sources.${name}.drvPath else null; }; }) (builtins.fromJSON ''"+json.dumps(names)+"''))"
current=json.loads(source_eval(selection))
require(all(not x["isDerivation"] for x in current.values()),"matching source did not materialize")
target=names[0]
try:
    stale=json.loads(original)
    stale[target]["drvPath"]="/nix/store/"+"0"*32+"-stale.drv"
    manifest.write_text(json.dumps(stale))
    run("git","add",str(manifest),cwd=right)
    actual=json.loads(source_eval(selection))
    require(actual[target]["isDerivation"] and actual[target]["drvPath"]==json.loads(original)[target]["drvPath"],"stale source did not fall back")
    require(all(not actual[n]["isDerivation"] for n in names if n!=target),"unrelated source changed")
finally:
    run("git","reset","--hard","HEAD",cwd=right)
try:
    corrupt=json.loads(original)
    corrupt[target]["narHash"]="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    manifest.write_text(json.dumps(corrupt))
    run("git","add",str(manifest),cwd=right)
    r=subprocess.run(["nix","eval","--impure","--raw","--option","eval-cache","false","--option","allow-import-from-derivation","false","--expr",prefix+"toString sources."+target],cwd=right,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (root/"invalid-hash.log").write_text(r.stdout)
    require(r.returncode!=0 and re.search(r"^\s*error: .*hash.*(?:mismatch|does not match)",r.stdout,re.M|re.I),"bad NAR hash not rejected with expected error")
finally:
    run("git","reset","--hard","HEAD",cwd=right)
try:
    data=next(p for p in sorted((asset/"data"/target).rglob("*")) if p.is_file())
    with data.open("ab") as f:
        f.write(b"\ndiagnostic corruption\n")
    run("git","add",str(data),cwd=right)
    r=subprocess.run(["python3",str(asset/"verify.py"),"--require-current"],cwd=right,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (root/"corrupt-source.log").write_text(r.stdout)
    require(r.returncode!=0 and re.search(r"^RuntimeError: "+re.escape(target)+r": tracked NAR does not match manifest$",r.stdout,re.M),"corrupt source was not rejected")
finally:
    run("git","reset","--hard","HEAD",cwd=right)
(root/"negative-controls.json").write_text(json.dumps({"matching":current,"stale":actual,"bad_hash":"rejected","corrupt_source":"rejected"},indent=2)+"\n")
print("MATERIALIZED_SOURCE_CONTRACT=success")
