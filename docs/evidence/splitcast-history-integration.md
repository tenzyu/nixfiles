# SplitCast history integration probe

On 2026-11-02, `origin/main` was `af1814707eea06f79a5076203d58cbd7b26bbe7b`. The SplitCast worktree remained dirty at `3cf330792d31df0721289d91e5643aa5fdee8f77`. No branch was deleted or updated by these merge probes.

The preserved neko5 repository is `/home/tenzyu/.cache/nixfiles-neko5-handoff.idP5C2FY/.nixfiles`. Its `implement/feature-projection` head is `77735558f46d08d126d6b31f65f9be03d786a59d`. A virtual `git merge-tree --write-tree` of that commit and `origin/main` returned tree `279031d6d72c87f4b8dec5f457c6eae72302f3b9` without conflicts.

To verify more than conflict resolution, a detached worktree at `/tmp/opencode/splitcast-projection-integration` was created from `origin/main`. The preserved commit was fetched from the backup and merged there with `git merge --no-commit --no-ff FETCH_HEAD`. The merge is intentionally uncommitted. `nix flake check --no-build path:/tmp/opencode/splitcast-projection-integration` exited 0. `nix build --no-link --print-build-logs --max-jobs 1 --cores 2 path:/tmp/opencode/splitcast-projection-integration#checks.x86_64-linux.projection` also exited 0. These checks do not include the dirty SplitCast changes and do not authorize activation.

The preserved `feat-framework-v2-codex` head `90b22c69beb39bf85bef309eca50306d348ecd16` conflicts with `origin/main` in ten feature files, including `ssh.nix` and `packages-desktop.nix`. A virtual merge cannot determine the intended behavior. The branch and its history remain preserved. The backup's `feat-framework-v2`, `origin`, and `perf-graphics-gaming-cleanup` heads produced the unchanged main tree in the virtual probes. Their ancestry must still be checked before any branch deletion.

The tracked SplitCast changes were then applied to the temporary merge with `git apply --3way`, and the SplitCast modules and package were copied after checking that their destinations did not exist. After the SSH recovery edit, its two changed package files were copied into the temporary worktree. `nix flake check --max-jobs 1 --cores 2 --print-build-logs path:/tmp/opencode/splitcast-projection-integration` exited 0 with `all checks passed!`. Cached checks were reused. This does not establish runtime acceptance.

Neither the original worktree nor the backup was cleaned. The temporary worktree is retained for inspection and must not be mistaken for an integrated or deployed result.
