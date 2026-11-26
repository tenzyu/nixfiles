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

Nix determines which store paths are live. Do not infer free space from closure size, delete a live path, remove arbitrary GC roots, or use `--ignore-liveness`. Ordinary `sudo nix-store --gc` deletes only dead store paths; run only after separate operator approval. Keep booted, active, pending-boot and rollback generations plus user profiles and project roots. Do not use blanket `nix-collect-garbage -d` as routine maintenance. Generation pruning is not part of this repository's workflow.

Review individual build result symlinks through their owning projects; deletion requires separate approval. Never prune while system references disagree. See [native Nix GC manual](https://releases.nixos.org/nix/nix-2.36.0/manual/package-management/garbage-collection.html) and the [historical cleanup implementation](../archive/README.md). This change does not run GC or remove files on any host.
