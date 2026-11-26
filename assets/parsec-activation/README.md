# Parsec activation and settings review

The two Home Manager hooks run after `writeBoundary` and use the native
`run` function. Dry-run prints the actions without opening the Parsec files
or creating a directory. `local.parsecActivation` supplies the two leaf names,
the controller ID, and the mode. The `parsec` feature also installs
`parsec-activation-review` alongside `parsec-xwayland`.

## Why these settings exist

The first Parsec module declared `decoder_software=0` (hardware decoding),
`client_decoder_h265=1` (try HEVC with H.264 fallback), `client_vsync=0`, and
`client_overlay_warnings=1` (show network and hardware warnings). The source
records the values. A preference for lower client latency is an inference from
hardware decode and VSync off, and Parsec documents the latency and tearing
tradeoff. The commit supplies no benchmark or reason for each choice.
[Original client settings](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L13-L24)
· [Parsec advanced options](https://support.parsec.app/hc/en-us/articles/32381443626516-All-Advanced-Configuration-Options)

The same source identifies the neko5 Dynabook touchpad as `HID Controller #14`
(`06CB/83D7`) and describes a constantly active fake gamepad. It uses an
all-unmapped row for that one ID and separately sets SDL environment variables
in the XWayland launcher to limit false controller detection. Parsec documents
per-controller mapping and unmapping in the Gamepad section of Settings. The on-disk
`_00` row and the effect of the SDL flags on this device come from repository
history. Current behavior on neko5 and the effect on real controllers remain
unverified here.
[Original launcher](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L50-L66)
· [Original mapping hook](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L90-L112)
· [Parsec Linux Gamepad settings](https://support.parsec.app/hc/en-us/articles/32381494397332-Parsec-App-for-Linux#gamepad)
· [Parsec stuck inputs guidance](https://support.parsec.app/hc/en-us/articles/32361336267412-Parsec-Constantly-Pressing-or-Scrolling-Up-Down)

The original module records an `EROFS` error when a Home Manager store
symlink was used for `config.txt`. Parsec documents that, since `150-89`, it
imports legacy assignments into `~/.parsec/config.json` on restart and clears
the imported settings from `config.txt`. The committed Linux package version
is `150_104a`. Parsec documents editing `config.json` directly with settings
stored in `{"value": …}` objects, then restarting the app. The first-run seed
uses that native format. First-launch behavior remains a host acceptance check.
[Original write rationale](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L71-L87)
· [Current package and seed](../../modules/50-features/services/parsec.nix)
· [Parsec configuration and migration](https://support.parsec.app/hc/en-us/articles/32381346632596-Accessing-Your-Advanced-Settings)

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

## Review an existing installation

1. Run `parsec-activation-review` as the affected user. It prints the four
   declared values with their status in the observed saved config, any pending
   assignments for those keys in `config.txt` alongside `config.json`, and the
   count and match for controller ID `06cb,83d7`. It prints the desired row
   when a mapping is absent or different. Other settings and actual file
   values stay out of the output.
2. Review client settings in Parsec. For gamepad behavior, select the affected
   controller in the Gamepad section of Settings and check raw input and per-button
   mappings. For a separate file edit, first make and verify an independent
   backup and establish control of every writer. Reconcile only the desired
   keys or the declared controller row, and preserve every unrelated mapping
   row in its original order. A closed window alone cannot establish control
   of all writers. [Parsec gamepad setup](https://support.parsec.app/hc/en-us/articles/32381705301908-Setup-Gamepad)
3. For an advanced config edit, use Parsec's documented restart procedure
   and review again after it saves. Verify client settings and controller
   behavior separately in the app. [Parsec configuration and migration](https://support.parsec.app/hc/en-us/articles/32381346632596-Accessing-Your-Advanced-Settings)

An older Home Manager store link can still block Parsec from writing or
clearing the linked file. Activation preserves it. Reconcile the link
separately with a verified backup and all writers stopped before expecting
Parsec to write the file.

The command exits `0` when the compared settings, mapping and applicable
modes match. It exits `1` for differences, missing required data, ambiguous
legacy input or an unsafe entry, and `74` for I/O errors. JSON comparison uses
the documented `{"value": …}` objects with numeric values for these four keys.
The command compares saved file observations. Runtime precedence, negotiated
codec, effective decoding and controller behavior require app observations.
After `OutcomeUnknown`, run the review before retrying. Retrying preserves
any final entry that is already visible.

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

## Fixture evidence

Run `nix build -L --no-link .#checks.x86_64-linux.parsec-activation` to exercise
the evaluated Home Manager hooks with the pinned `run` function and the
packaged review command in isolated `HOME` directories. The fixtures check
`INTENT-01` dry-run, `BOUNDARY-01` symlink and parent
refusal, `PUBLISH-01` new files and concurrent collision, `PUBLISH-02` failures
before and after link, `OWNED-01` preservation of unreadable files, legacy
store links and simulated app saves, and `RECOVERY-01` repeat behavior.
A separate process creates app-owned
JSON just before the kernel link. The fixture checks that the winner's bytes
and mode survive and no `config.txt` is created. Legacy entries are tested
before and at publication. Review fixtures check diagnostics, exit status,
and unchanged bytes and metadata. The injected flush errors simulate
publication faults. Real-host Parsec acceptance is **NOT RUN**.
