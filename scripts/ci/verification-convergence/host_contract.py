"""Diagnostic checks on isolated historical worktrees. Never admit a PR."""
import json
import os
import subprocess
import sys
from pathlib import Path

BASE, CANDIDATE = sys.argv[1:3]
root = Path(os.environ["RUNNER_TEMP"]) / "contract"
root.mkdir()

def command(*args, cwd=None, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()

def check(condition, msg):
    if not condition:
        raise RuntimeError(msg)

def worktree(name, ref):
    path = root / name
    command("git", "worktree", "add", "--detach", str(path), ref)
    return path

def step(path, name):
    lines = (path / ".github/workflows/compute-host.yml").read_text().splitlines()
    start = lines.index("      - name: " + name)
    run = lines.index("        run: |", start)
    body = []
    for line in lines[run+1:]:
        if line and not line.startswith("          "):
            break
        body.append(line[10:])
    check(bool(body), "empty workflow step")
    return "\n".join(body) + "\n"

def run_step(path, name, suffix):
    output = root / (suffix + ".output")
    output.touch()
    env = dict(os.environ, GITHUB_OUTPUT=str(output))
    r = subprocess.run(["bash", "-e", "-c", step(path, name)], cwd=path, env=env,
                       text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (root / (suffix + ".log")).write_text(r.stdout)
    print(suffix, r.returncode, r.stdout[-3000:])
    return r

def native(path, attr):
    return command("nix", "eval", "--raw", ".#checks.x86_64-linux." + attr + ".drvPath", cwd=path)

base, candidate = worktree("base", BASE), worktree("candidate", CANDIDATE)
checks = ("compute-host-container", "tailnet-ingress", "workload-lifecycle")
before = {n: native(base, n) for n in checks}
after = {n: native(candidate, n) for n in checks}
check(before == after, "native test derivations changed")
old_step = "Evaluate production deployment boundaries"
check(run_step(base, old_step, "old-positive").returncode == 0, "old policy rejects baseline")
check(run_step(candidate, old_step, "new-positive").returncode == 0, "new policy rejects candidate")
p = candidate / "modules/10-foundations/compute-host-checks.nix"
original = p.read_text()
needle = "host = self.nixosConfigurations.neko7.config;"
check(original.count(needle) == 1, "host boundary changed")
cases = [
    ("compute-host-container", 'virtualisation.incus.preseed.config."core.https_address" = lib.mkForce "0.0.0.0:8443";', "private-listener"),
    ("tailnet-ingress", "local.features.tailnet-ingress.enable = lib.mkForce false;", "enabled"),
    ("workload-lifecycle", 'containers.neko7-mc.path = lib.mkForce "/tmp/diagnostic-wrong-profile";', "minecraft-profile"),
]
for attr, override, failure in cases:
    try:
        p.write_text(original.replace(needle, "host = (self.nixosConfigurations.neko7.extendModules { modules = [ ({lib, ...}: {" + override + "}) ]; }).config;"))
        command("git", "add", str(p), cwd=candidate)
        r = subprocess.run(["nix", "eval", "--raw", ".#checks.x86_64-linux." + attr + ".drvPath"], cwd=candidate, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (root / (attr + ".negative.log")).write_text(r.stdout)
        print(attr, r.returncode, r.stdout[-2000:])
        check(r.returncode != 0 and "host contract violations:" in r.stdout and failure in r.stdout, "negative control failed: " + attr)
    finally:
        command("git", "reset", "--hard", "HEAD", cwd=candidate)
try:
    needle = '(name: self.packages.\u0024{system}.\u0024{name}.drvPath);'
    check(original.count(needle) == 1, "deployment graph changed")
    p.write_text(original.replace(needle, '(name: host.system.build.toplevel.drvPath);'))
    command("git", "add", str(p), cwd=candidate)
    r = run_step(candidate, old_step, "closure-negative")
    check(r.returncode != 0 and "is coupled to the host generation" in r.stdout, "closure coupling accepted")
finally:
    command("git", "reset", "--hard", "HEAD", cwd=candidate)
(root / "receipt.json").write_text(json.dumps({"base": BASE, "candidate": CANDIDATE, "native_derivations": before, "negative_controls": [c[2] for c in cases]+["closure-coupling"]}, indent=2))
