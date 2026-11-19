# Private Shell safety operations

Source the file returned by `pkgs.callPackage ./assets/safety/shell {}` in a dedicated subshell running Nix-pinned Bash. The fixed native helper uses Python for `fsync(2)` on the actual open descriptors and Linux `linkat(2)` on two leaves in the open directory. Nix pins Bash and ShellCheck in the check and substitutes store paths for the library's runtime tools.

The fixed-purpose caller authorizes the actor, root and final leaf before entering the mutation subshell. The root must be an existing canonical absolute directory owned by the effective UID, with no group or other write permission. The caller must establish that the root, its ancestors, the pre-provisioned regular `.safety.lock`, and the stage entry remain trusted throughout the operation. Use a local Linux filesystem with working `flock`, hard links and file and directory fsync. The stage and final occupy the same directory. Observed parent moves and stage substitutions cause refusal or an unknown outcome. A pathname check followed by another operation cannot protect against a writer that can change the namespace between those steps.

- `safety_lock root` takes a nonblocking exclusive `flock` on the existing lock inode. Contention returns 73. This coordinates callers that use the same inode and lock type. The lock stays held until the last inherited descriptor closes, including when a child outlives the shell. Keep the subshell open through any caller recovery. Only trusted children may inherit the descriptors. The caller must join all writers before publication or cleanup and must keep descriptor inheritance within the chosen actor.
- `safety_stage leaf` creates a fresh regular 0600 stage. `safety_stage_fd` is the write handle and `safety_stage_path` can be reopened for validation. The final name is a single leaf, with `.safety.lock` and `.safety-stage.*` reserved. Stop on a write or validation error.
- `safety_publish_new` flushes the staged file, links it to the final leaf in one native call, confirms the entry and flushes the open parent directory. An existing entry of any type is a conflict. The caller must invoke this only after its payload validation succeeds.
- `safety_finish "$?"` is the subshell's EXIT handler. It removes only the stage entry still identified by the held descriptor. It leaves the lock entry in place. A cleanup failure reports whether final publication was confirmed and keeps an existing command failure status. The stage unlink happens after the parent flush, so a crash can leave a stage name to reconcile.

This example assumes approval, selection of the fixed root and leaf, and synchronous producer and validator functions.

```bash
(
  source "$safety_library"
  trap 'safety_finish "$?"' EXIT
  trap 'printf "Interrupted: TERM\n" >&2; exit 143' TERM
  trap 'printf "Interrupted: INT\n" >&2; exit 130' INT
  trap 'printf "Interrupted: HUP\n" >&2; exit 129' HUP
  safety_lock "$approved_root" || exit "$?"
  safety_stage "$selected_leaf" || exit "$?"
  write_payload >&"$safety_stage_fd" || exit "$?"
  validate_payload <"$safety_stage_path" || exit "$?"
  safety_publish_new || exit "$?"
)
```

`Denied` uses 64, `Unsupported` uses 69, and `Conflict` uses 73. The native adapter reports errno and uses 74 for known I/O failures or 75 for an ambiguous link outcome. A parent flush error reports `OutcomeUnknown` and returns the flush status. Unexpected link status and interruption while linking or flushing also report `OutcomeUnknown`, preserving the observed failure status. A failure before link leaves no new final. On uncertainty, the handler retains the stage. Inspect the actual final and stage before any retry. A failed cleanup, a kill or an interruption before the stage handle was acquired can also leave a stage. Inventory leftovers by inspection. Never sweep the stage prefix or remove a final as part of retrying.

The [fixture contract](../../../fixtures/contracts/safety-shell.md) records what the Nix check exercises.
