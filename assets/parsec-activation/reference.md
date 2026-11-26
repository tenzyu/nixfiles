# Parsec seed and publication rules

## Compatibility review gate

[#55](https://github.com/tenzyu/nixfiles/pull/55) switched activation to
missing-file seeding. The config hook now seeds only `config.json`, with four
numeric settings at mode `0600`. Existing `config.json` remains app-owned.
Any observed `config.txt` entry suppresses the JSON seed. That includes empty
files, symlinks, and special files. Parsec retains control of legacy imports.
The `gpmap.txt` seed runs independently when its destination is absent.
An incumbent at either seed destination is sufficient to skip that seed.
Activation reports the skip without opening the file. The review command
compares contents and modes and reports read errors.

## Publication boundary

The actor is the unprivileged activation user. The adapter holds directory
descriptors for canonical, user-owned `HOME` and `.parsec` directories without
group or other write access. It can create `.parsec` with mode `0700` when
it is missing. Symlinks, non-directory parents, or an unsupported staging or
link operation warn and skip the affected seed. Existing leaf symlinks and
special files warn without following them. A failed presence check or
pre-publication I/O failure returns nonzero.

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
inode. If Parsec creates `config.json` first, activation's link to the same
name fails and the app's file wins. If activation publishes first, Parsec can
edit the seed as it would any saved configuration. The adapter checks for
`config.txt` before staging and again just before the link. A legacy entry
that arrives after the last check remains the user's input for Parsec to
import. If activation observes that entry immediately after linking, it
reports both names and directs the user to review. Seed with Parsec fully
stopped if legacy import must take precedence. Review reports observations
of individual files that can change independently while the app is running.

After `OutcomeUnknown` or process interruption, inspect both final leaves
before retrying. A final file may already be visible. Do not delete it to
force a retry. A retry will leave an existing file alone; it does not certify
durability of a prior uncertain link. The operation requires working Linux
procfs, `O_TMPFILE`, hard links, and fsync on the target filesystem. Filesystem
support on the live host is not established by evaluation.

See the [settings review procedure](README.md).
