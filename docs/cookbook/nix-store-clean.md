# Nix store maintenance

Nix owns store reachability and garbage collection. The `nix` feature enables native automatic GC with `--delete-older-than 7d`. This retires generations older than the configured age under Nix's own retention rules before collecting unreachable store paths. The operator's manual GC command does not prune generations.

Run these read-only inventory commands:

```sh
readlink -f /run/current-system /run/booted-system /nix/var/nix/profiles/system
nix-store --gc --print-roots
nix-store --gc --print-dead
nix path-info -Sh /run/current-system
df -h /nix/store
```

Nix determines which store paths are live. Do not infer available disk space from closure size. Do not delete live paths, remove arbitrary GC roots, or use `--ignore-liveness`. Run `nix run .#operator -- store-clean` for explicit manual GC. It requires an interactive terminal, checks that the current, booted and system profile generations agree, displays native dead paths, requires typing `GC`, and rechecks the generation before calling the daemon through sudo. Nix re-evaluates reachability at execution. This command retains existing roots and generations; it does not disable the independent automatic GC policy. Do not use blanket `nix-collect-garbage -d` as routine maintenance.

Review each build result symlink in its project. Obtain separate approval before deletion. Do not manually prune generations while system references disagree. See [native Nix GC manual](https://releases.nixos.org/nix/nix-2.36.0/manual/package-management/garbage-collection.html) and the [historical cleanup implementation](../archive/README.md).
