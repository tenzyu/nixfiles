# Nix store maintenance

Use native Nix GC; no custom GC-root classifier, interactive cleanup program or automatic generation retirement.

Run these read-only inventory commands:

```sh
readlink -f /run/current-system /run/booted-system /nix/var/nix/profiles/system
nix-store --gc --print-roots
nix-store --gc --print-dead
nix path-info -Sh /run/current-system
df -h /nix/store
```

Nix determines which store paths are live. Do not infer available disk space from closure size. Do not delete live paths, remove arbitrary GC roots, or use `--ignore-liveness`. `sudo nix-store --gc` deletes only dead store paths. Obtain separate operator approval before you run it. Keep the booted, active, pending-boot, and rollback generations. Retain user profiles and project roots. Do not use blanket `nix-collect-garbage -d` as routine maintenance. Generation pruning is not part of this repository's workflow.

Review each build result symlink in its project. Obtain separate approval before deletion. Never prune while system references disagree. See [native Nix GC manual](https://releases.nixos.org/nix/nix-2.36.0/manual/package-management/garbage-collection.html) and the [historical cleanup implementation](../archive/README.md). This change does not run GC or remove files on any host.
