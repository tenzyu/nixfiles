# Parsec activation: create missing files, keep existing data

The two Home Manager hooks run after `writeBoundary` and use the native
`run` function. Dry-run prints the actions without opening the Parsec files
or creating a directory. `local.parsecActivation` supplies the two leaf names,
the controller ID, and the mode. Disabling the feature removes both hooks.
The XWayland launcher and desktop entry are unchanged.

## Compatibility review gate

**Approve this behavior change before merging.** An existing `config.txt` with
different bytes, or a `gpmap.txt` without exactly one matching `06cb,83d7` row,
used to be rewritten. Now it stays as it is, even when it is a valid Parsec
file. An otherwise matching file with a different mode also stays as it is.
Each of these cases emits a warning but does not block Home Manager. The
warning means the declaration was **not** applied to that file. A matching
`gpmap.txt` needs no rewrite regardless of the other rows or their order.

To apply the intent to an existing installation, use Parsec's own settings
where they cover it. For a separate file edit, make and verify an independent
backup, establish control of every writer of the file, and review the intended
diff against the [module declaration](../../modules/50-features/services/parsec.nix).
For `gpmap.txt`, reconcile only the declared controller row. Preserve all other
bytes and row order. Verify mode `0600` separately. A process check or closing
the UI is not proof that all writers are excluded. If you cannot establish that
control, leave the file alone. Activation never deletes, moves, or chmods an
existing entry to force a match. A Git revert will not remove a file that has
already been seeded and would restore the previous overwrite behavior.

## Publication boundary

The actor is the unprivileged activation user. The adapter holds directory
descriptors for canonical, user-owned `HOME` and `.parsec` directories without
group or other write access. It can create `.parsec` with mode `0700` when
it is missing. Symlinks, non-directory parents, or an unsupported staging or
link operation warn and skip the affected seed. Existing leaf symlinks and
special files warn without following them. Read failures and pre-publication
I/O failures return nonzero, not empty data.

The [Shell core](../safety/shell/README.md) requires a trusted named stage and
lock entry. Neither is established in Parsec's writable directory. Instead
this adapter stages with Linux `O_TMPFILE` on the target filesystem, validates
the bytes and mode `0600`, then uses the core's descriptor fsync helper. It
links the staged inode via `/proc/self/fd` to the final leaf in the open
directory. `linkat` refuses any existing destination entry. It does not
overwrite or follow the destination leaf. There is no named stage to clean
up and no fallback to the old `gpmap.txt.tmp` path. After the link, the helper
flushes `.parsec` and `HOME`. The two independent seeds are not a transaction.

An observation of a path does not reserve it. The directory descriptor can
still refer to a moved directory. A move detected before link aborts the seed;
a move or failed confirmation detected after link reports `OutcomeUnknown`.
An undetected concurrent rename can put the new file in the originally opened
directory at its new location. The no-replace guarantee is for that directory
inode. No check excludes Parsec or another user writer, prevents a later edit,
or defends against a hostile process with access to the activation process's
descriptors. There is no inode compare-and-swap. This design never attempts
existing-file replacement.

After `OutcomeUnknown` or process interruption, inspect both final leaves
before retrying. A final file may already be visible. Do not delete it to
force a retry. A retry will leave an existing file alone; it does not certify
durability of a prior uncertain link. The operation requires working Linux
procfs, `O_TMPFILE`, hard links, and fsync on the target filesystem. Filesystem
support on the live host is not established by evaluation.

## Fixture evidence

Run `nix build -L --no-link .#checks.x86_64-linux.parsec-activation` to exercise
the evaluated Home Manager hooks with the pinned `run` function and an isolated
`HOME`. The fixtures check `INTENT-01` dry-run, `BOUNDARY-01` symlink and parent
refusal, `PUBLISH-01` new files and concurrent collision, `PUBLISH-02` failures
before and after link, `OWNED-01` refusal to replace existing files, and
`RECOVERY-01` repeat behavior. They check bytes and metadata, not just exit
status. The injected flush errors are not a power-loss test. No app is launched
and no regular Home Manager activation runs.
