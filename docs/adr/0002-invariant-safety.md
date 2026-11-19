# ADR-0002 — Preserve existing data at commit boundaries

- **Status:** Accepted (architecture and operator policy). Convergence implementation is under review. Real-host acceptance **NOT RUN**.
- **Date:** 2026-11-19
- **Original proposal baseline:** [`0daacae75f19dc2b01712c26471b42b2c6bc9ca3`](https://github.com/tenzyu/nixfiles/commit/0daacae75f19dc2b01712c26471b42b2c6bc9ca3)
- **Scope:** Minecraft backups, Parsec activation, Home migration, and build-result GC roots. Other mutation paths are inventoried for regression review, not scheduled for a blanket rewrite.

## Context

The examples, original delivery gates, and closeout below record the historical proposal and PRs #48–#59. The [convergence decisions](#convergence-decisions) record the later approvals that supersede earlier behavior.

These paths already have safeguards, but a preflight check does not reserve a path or exclude another writer. A completed command is also not proof that an archive is valid, a directory entry is durable, or a service has recovered. The source below shows conditional failure paths, not observed incidents or current host state.

| Invariant and source at baseline | Actor and authority | Current commit point and recovery limit |
| --- | --- | --- |
| **I-1 · Preserve Parsec user data (P1).** [Activation hooks](https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/50-features/services/parsec.nix#L78-L112) | User Home Manager on `neko5`, after `writeBoundary`. It declares all of `config.txt`, but only one controller ID in `gpmap.txt`. Parsec or another user process may write in the same directory. | The hooks write `config.txt` directly and move a fixed temp over `gpmap.txt`. The latter ignores `grep` errors as well as no matches. Neither path proves that the previous data or unrelated mappings can be recovered. |
| **I-2 · Publish only complete new Minecraft archives (P1).** [Command wrapper](../../modules/50-features/game-servers/commands.nix), [backup path](https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/modules/50-features/game-servers/_internal/game.sh#L142-L165) | The host operator controls the guest unit. The game UID writes the archive. The guest can also write the data tree. `neko7` selects Minecraft, the service data layout, and the tools. The [guest module](../../modules/50-features/game-servers/minecraft.nix) already uses `nix-minecraft` and its overlay. | The script starts the container if needed, tests running state, and stops the guest unit if running. `tar` writes directly to a final name with one-second resolution. Failure can leave a partial final and leaves the server stopped. A false running test does not distinguish inactive from an observation error. |
| **I-3 · Preserve Home data during migration (P1).** [Activation check](../../modules/50-features/home/home-migration.nix), [planner and apply](https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/assets/home-layout/migrate.py#L170-L385) | Home Manager checks only. The user separately authorizes `apply` against the manifest's HOME, XDG destinations, and migration state. Apps and other user processes remain possible writers. | The planner checks the batch. Moves use `RENAME_NOREPLACE` and flush both parent directories. Symlink repair and reference rewrite use `os.replace`. Repair flushes the parent, but a rewrite's staged file flush does not establish durability of its final entry or backup. A journal entry alone is not proof of completion. |
| **I-4 · Remove only the selected build-result link (P2).** [Root selection and unlink](https://github.com/tenzyu/nixfiles/blob/0daacae75f19dc2b01712c26471b42b2c6bc9ca3/assets/nix-store-clean/cli.py#L196-L269) | The normal user selects their own eligible project `result` links on a terminal and confirms with `UNLINK`. This is not authority to delete store paths. A build or another project process can change the link. | The cleaner refreshes roots and checks link attributes before pathname `unlink`. A different entry can occupy that name by commit time. Recovery starts by inspecting the link and native root list again. It cannot assume the store target will remain live. |

### Other authority boundaries to preserve

| Path | Actor, commit, and recovery boundary |
| --- | --- |
| [Generation pruning and GC](../cookbook/nix-store-clean.md) | The confirmed root operator uses native profile deletion and runs native GC separately. Keep the booted, current, and profile references valid. Pruning requires them to agree. Native liveness still governs GC. Keep staged-boot and rollback VM acceptance separate from fixture checks. Git cannot recover collected paths. |
| [Game update and retention](../cookbook/game-server-features.md) | ARK and Rust are disabled in `neko7` source. Their updater and retention paths stay inactive there. In an enabled configuration, the guest updater installs data and retention deletes backups. Recovery belongs to that game's operator and requires retained data. Minecraft keeps its declarative update path. |
| [Tailscale Serve](../../modules/50-features/networking/t3code-tailnet.nix) | The operator authorizes a one-shot restore of the declared route. A match is a no-op and a conflict is refused. The commit changes daemon state. Read back that state before any further approved restore, rather than clearing existing routes. |
| [SOPS](../cookbook/secrets-and-tailscale.md) and [remote builder](../cookbook/nix-trust-boundary.md) | The operator owns credentials, decryption, and trust changes. The activation and daemon boundaries apply the approved permissions and access. Check them without copying secrets into logs. A selected provider or successful evaluation proves neither decryption nor working access. Restore access only through a separately approved operation. |
| [osu! labs](../../scripts/osu-performance/README-lab.md) | The user owns the test session. Runtime changes take effect when the lab applies settings or starts a test process. End the session and verify cleanup and restoration before reusing the baseline. Telemetry is not physical latency evidence. |
| [Framework CLI](../../tools/framework-cli) and [direnv hook](../../assets/opencode/direnv.ts) | The caller has separate read and explicit-execution paths. The hook keeps its approval gate. Execution crosses the boundary at process spawn. Preserve failure status and check for side effects before retrying. |
| [CI and cache](../../.github/workflows/nix-validation.yml) | The runner selects checks and reports verdicts. Cache publishers own signing and publication. The audit distinguishes reachable metadata from a verified signed copy. A failure calls for inspection or a rerun of the applicable check, not bypassing trust or publishing a replacement. |

## Decision

Share contract IDs and expected observations. Keep enforcement in the layer that owns the file descriptor, child process, or systemd unit. Each mutation names its actor, allowed root and target, other writers, visibility point, and recovery evidence. When a required guarantee is unavailable, refuse the mutation before changing data or offer a read-only proposal.

[ADR-0001](0001-canonical-feature-semantics.md) constrains 2d and 2f. Preserve the typed host interface and explicit feature lists. A host seed of `null` contributes no target definition. An explicit boolean follows native NixOS and Home Manager precedence. Preserve explicit `false` in embedded Home Manager, trace's winning priority, and `null` for unknown priority. Disabled features must not gain units or packages as a side effect of this work.

| Contract | Required behavior and limit |
| --- | --- |
| `Intent` and `Authority` | Separate read-only and mutation entry points. Bind the operation, actor, approved root, and target selection in an immutable intent. Unrecognized operations, disallowed targets or types, and missing confirmations are `Denied`. A check or dry run creates no root, lock, stage, or journal. Keep secret values out of argv and logs. |
| `Boundary` | Resolve relative components under an open, authorized directory descriptor where the implementation supports it. State how the operation handles parent moves, symlinks, `..`, absolute input, non-directories, and filesystem boundaries. An open descriptor can still refer to a moved directory. It does not prove the displayed path or final leaf still names the same object. Shell pathname operations require a trusted parent and entry for the full operation. Otherwise return `Unsupported`. |
| `ExclusiveOperation` | Use one fixed lock identity in a stable parent. Define the inode, OS lock type, descriptor lifetime across child processes and privilege changes, and which writers participate. Hold the lock through commit and any required lifecycle recovery while children can still write. Do not remove and recreate the lock name on exit. `flock` coordinates only compliant writers. Process names and probes do not prove exclusion. |
| `Stage` and `PublishNew` | Create a private regular stage on the final filesystem and keep a handle that identifies the owned stage. Write, validate, flush the file, publish atomically without replacing the final leaf, then flush the parent directory. An existing regular file, symlink, or directory is a `Conflict`. Do not publish inside an existing directory or fall back to copies or overwriting renames. An unsupported filesystem operation is `Unsupported`, not success. |
| `ReplaceOwned` | Use a separate path for replacing existing data. The caller must establish ownership of the content and update scope, preserve required mode and unrelated data, and account for every writer. A check followed by rename is not an inode compare-and-swap. Refuse read-modify-write if another writer can invalidate the check, or get approval for a different ownership boundary. |
| `Failure` and `Recovery` | Record `Conflict`, `Denied`, `Unsupported`, `Interrupted`, or `OutcomeUnknown` when applicable. Keep the underlying I/O cause, errno, or exit status where available. Before publication, a failure creates no new final. After publication, a failed flush or observation can leave a visible final. Report uncertainty rather than success or absence. Reconcile the final, owned stage, and any journal by inspection before a retry. Cleanup touches only the stage owned by this invocation. After a kill, inventory abandoned stages without sweeping them or deleting a final to start over. |

[`link(2)`](https://man7.org/linux/man-pages/man2/link.2.html) and [`renameat2` with `RENAME_NOREPLACE`](https://man7.org/linux/man-pages/man2/rename.2.html) can establish no-replace publication where supported. They do not establish the resolution, locking, or durability guarantees described by [`openat2(2)`](https://man7.org/linux/man-pages/man2/openat2.2.html), [`flock(2)`](https://man7.org/linux/man-pages/man2/flock.2.html), and [`fsync(2)`](https://man7.org/linux/man-pages/man2/fsync.2.html). If Shell uses a hard link to publish, use [GNU `-T` semantics](https://www.gnu.org/software/coreutils/manual/html_node/Target-directory.html) for the final leaf. The exit status of `mv -n` does not prove publication.

For example, `game backup minecraft` uses the actor, roots, and unit supplied by the Nix wrapper. The lifecycle owner checks the unit and stops it if needed under the game lock. The game UID stages, validates, and publishes the archive. The command keeps the publication and restart results separate. It does not hand an arbitrary stage path to a separate privileged command.

### Alternatives rejected

A common privileged command, a cross-language RPC layer, or a transaction engine would expand authority and packaging costs. A check in one process followed by a commit in another does not carry the first process's guarantees across that boundary. Use a fixed-purpose command and only the operations its caller can verify. Shell stays unprivileged as a shared implementation. Python can use immutable actions and directory descriptors. TypeScript can validate runtime inputs and run argument vectors without a shell. Rust can demonstrate descriptor ownership without entering host closures. Nix supplies types, assertions, and native unit and activation ordering.

## Shared fixture taxonomy

The IDs below name proposed cases, not test files or passing results. A case records the ID, pre-state, actor and approved root, operation, injected failure or concurrent writer, expected result, observed state, and limits of the observation. Native runners exercise packaged code. If a language lacks an API for a case, report it as not applicable or unsupported, not passed.

| Fixture ID | Required observation |
| --- | --- |
| `INTENT-01` | Unknown operation, wrong actor or target, or missing confirmation denies mutation. Read-only and dry-run operations create no state. Secret-bearing inputs or child output do not leak through argv or logs. |
| `BOUNDARY-01` | Exercise absolute input, traversal, symlink and non-directory parents, a moved parent, and a different filesystem. The implementation rejects unsupported boundaries and acts only within the one it can prove. |
| `LOCK-01` | A second process using the same inode and lock type cannot enter while a child can still write. Where two implementations share a lock, test contention across them. Distinct inodes and non-participating writers do not get this guarantee. |
| `PUBLISH-01` | A successful write publishes one verified final with the intended mode. On a collision with a regular file, symlink (including dangling and directory-target links), or directory, compare existing inode, bytes, and mode where applicable. Check link targets and directory contents too. |
| `PUBLISH-02` | Test partial writes, `ENOSPC`, cancellation, signals, unsupported operations, and failure at file flush, publication, and parent flush. Assert the flush order and distinguish no new final from a possibly visible final. Never hide the failure exit status. |
| `OWNED-01` | Change a leaf or let an independent writer act after inspection. Require proof of exclusion for replacement or unlink, or refuse the operation. A matching value or a parent descriptor alone does not establish leaf identity. |
| `RECOVERY-01` | Test interruption, rerun, a leftover stage, and cleanup failure. Observe the real entries and any journal. An unrelated file and an already published final remain unchanged, even when cleanup or observation fails. |

## Delivery order and decision gates

2a is documentation only. After its manual merge, 2b is the first code PR and 2k may investigate in parallel. Prioritize 2f once the 2b contract is settled. Independent core work in 2c, 2d, and 2e does not wait for 2f. Minecraft is the first consumer to start. Parsec depends on the same core and policy but can proceed independently of Minecraft. Confirm prerequisite merges or recorded decisions before starting dependent changes. Do not rely on unmerged diffs. Coordinate shared check registration, and rerun selector tests when a branch updates to main.

| PR | Requires | Scope and exit gate |
| --- | --- | --- |
| 2a · ADR | Review of this proposal | Record invariants, writers, failure rules, fixture IDs, and limits. No test code or runtime changes. |
| 2b · Shell core | 2a | Package the private Shell operations with pinned inputs. Run ShellCheck and native Bash fixtures against the package in an isolated root, without real sudo or services. Prove the relevant shared cases, including stage ownership, lock lifetime, and errors after publication. No tar workflow, consumer wiring, or host changes. |
| 2c · Python core | 2a | Test immutable intent and descriptor-relative create-new using the standard library. Compare with the existing no-replace move and record limits. Keep `home-migration` green without changing the engine or rules. |
| 2d · TypeScript core | 2a | Check CLI parsing, argv execution, spawn errors, exit reporting, and output redaction. Preserve the hook's approved status gate, timeout, buffer, and event environment. Test its packaged form where needed. Add no filesystem API without a consumer. |
| 2e · Rust decision | 2a | Compare `OwnedFd` with `rustix` and `cap-std` in a small isolated crate outside host closures. Use locked `cargo test` and an unsupported-kernel case. Do not introduce a shared backend. If the demonstration is not worth maintaining, retain the fixture, rationale, and restart criteria and get explicit approval to defer. |
| 2f · Native policy | 2a | Use `lib/service-layout.nix`, native units, tmpfiles, and the Home Manager DAG for minimal types and assertions. Define the stable lock parent and unit owner. Evaluate ADR-0001 behavior and disabled-feature isolation. No new supervisor or hidden host opt-in. |
| 2g · Minecraft | 2b, 2f | Change only the enabled Minecraft backup path. Meet the I-2 gate below, run isolated restore and lifecycle cases, and evaluate the `neko7` derivation. |
| 2h · Parsec | 2b, 2f | Meet the I-1 gate below in an isolated HOME with the packaged activation path or its equivalent. Check idempotence, dry run, the `neko5` DAG, and derivation evaluation. |
| 2i · Game comparison | 2g complete | Research only. Compare the pinned `nix-minecraft`, native Minecraft module, LinuxGSM, steamcmd-servers, and Tailscale sharing. Require compatible guest identity, TUN, bind mounts, UID and GID, lifecycle ownership, restore, and reproducible packaging. Compare closure, configuration traceability, authority, and cost. Verify sharing terms and consent separately. Do not enable anything. |
| 2j · Game composition | Approved 2i decision | Adopt a package, take specific files, or retain the existing composition. If changing it, preserve service, world, backups, mounts, IDs, and recovery, and rerun 2g tests. An explicit retain decision closes this row without a no-op PR. |
| 2k · Home comparison | 2a | [Research report](0002-home-migration-research.md). Compare evaluated rule order and the declarations in `home-layout.nix`, `bundles/common.nix`, `cli/zsh.nix`, and `desktop/firefox.nix`. Record source, target, references, process guards, conditions, and conflict policy per rule. Distinguish setting a new destination from migrating existing data. Compare antidot's move and recovery code first, then xdg-ninja's diagnostics, boxxy's redirects, and pinned Home Manager collision checks. |
| 2l · Home adapter | 2c and approved 2k decision | Meet the I-3 gate below. Keep manual apply, batch preflight, and application-specific behavior. Test the packaged runner and give it the same dependencies as the tests. |
| 2m · Closeout | 2g, 2h, 2i and the 2j disposition, 2l, 2d, and the 2e disposition | Resolve I-4, review remaining mutation paths and check selection, and record why unchanged consumers stay as they are. Compare CI time under comparable runner and cache conditions, and closure size from existing outputs or approved sandbox builds. Mark unmeasured results as such. |

For 2i and 2k, record the review date, pinned revision, relevant files and dependencies, maintenance, license and notices, fixture evidence, and unmet requirements. Whole-package adoption needs evidence that every hard requirement holds. Partial adoption also needs exact files, attribution, an update plan, and tests for the extracted code. Stop when no remaining comparison could change the decision. Keep the small local adapter if evidence or compatibility is insufficient.

### Native policy outputs for 2g and 2h

**Game operations.** NixOS exposes the read-only option
`config.local.gameOperations.<game>` for `ark`, `minecraft`, and `rust`.
It is `null` unless both `game-<game>` and `game-server-tools` are enabled
after native feature resolution. The container and tools still have their
independent feature selections. Gate downstream operations on the option
because a lock from an earlier generation can persist until reboot.

| Field | Minecraft on `neko7` |
| --- | --- |
| `lockPath` | `/run/nixfiles-game-locks/minecraft.lock` |
| `containerName` | `neko7-mc` |
| `containerUnit` | `container@neko7-mc.service` in the host system manager |
| `guestUnit` | `minecraft-server-survival.service` in the guest system manager |
| `archiveUser`, `archiveUid`, `archiveGid` | Host account `game-minecraft`, UID and GID `27009`. The guest service runs as `minecraft` with the same numeric IDs. |
| `sourceDir`, `backupsDir` | `/srv/minecraft/survival`, `/srv/minecraft/backups` with `game-srv`. In the legacy layout the two leaves are under `/home/game-minecraft/minecraft`. |

Host `systemd.tmpfiles.settings.nixfiles-game-locks` declares a `d` entry for
`/run/nixfiles-game-locks` (`root:wheel`, `0750`) and an `f` entry for
`/run/nixfiles-game-locks/<game>.lock` (`root:wheel`, `0440`, no age or
contents). Recreation of a missing file belongs to native tmpfiles. Its plain
`f` rule preserves an existing regular inode. The lock has one inode across
cooperating invocations, tmpfiles reapplication, and independent container and
game-unit restarts within the same boot. Operators must leave the lock entry in
place. The game service HOME, data, backups, secrets, and Tailscale state are
outside this host namespace. The game account stays outside `wheel` and the
guest receives no lock bind mount. [Layout and policy definitions](../../lib/service-layout.nix)
· [Native host tmpfiles and account assertion](../../modules/50-features/game-servers/_internal/container.nix)

2g uses the existing authorized host operator (root or a `wheel` member with
the existing control authority) to coordinate lifecycle. Open the fixed
regular lock file read-only and take an exclusive Linux `flock(2)` on the open
file description. Require a trusted, local host `/run`, protected ancestry,
and the expected file type and ownership. Refuse missing, unsafe, or
unavailable locks. Keep the descriptor through state observation, any required
stop, publication and recovery, and retain it while a trusted child can still
write even if the coordinator exits. Direct unit control, arbitrary guest
background jobs, and other writers that bypass the lock remain outside its
guarantee. The existing native container and guest units own their lifecycles.

The Shell core's `safety_lock` uses a separate exclusive lock in the publication
scope. Its canonical root and regular `.safety.lock` must both belong to the effective
writer, `game-minecraft` for Minecraft. The host lock is held first and spans
the writer's entire operation and subsequent recovery. The writer uses the
private publication scope for its own stage and never treats the host lock as
that scope's `.safety.lock`. 2g must establish the publication ancestry
requirements and prove descriptor retention through any privilege transition.
In particular, ordinary `sudo` may close inherited descriptors. If the
existing invocation cannot preserve control and retention safely, the
mutation must refuse before stopping the unit or writing data. 2f supplies
neither a sudo grant nor a privileged launcher. [Shell core contract](https://github.com/tenzyu/nixfiles/pull/50)

**Parsec.** The effective Home Manager `config.local.parsecActivation` is
read-only, with `null` when Parsec is disabled. When enabled, it exposes
`directory = ".parsec"`, `configFile = "config.txt"`,
`mappingFile = "gpmap.txt"`, `mappingId = "06cb,83d7"`, and `mode = "0600"`.
Use the activation user's `$HOME`, corresponding to `config.home.homeDirectory`
and `config.home.username`. On `neko5` this is `tenzyu` under
`/home/tenzyu/.parsec`. The native `home.activation.parsecConfig` and
`home.activation.parsecTouchpadGpmap` entries both follow `writeBoundary`
in the existing user DAG. The declaration controls the full contents of
`config.txt` and only the row with the declared ID in `gpmap.txt`. 2h must
account for other writers within those scopes and honor Home Manager dry-run
semantics. [Parsec feature](../../modules/50-features/services/parsec.nix)

### Consumer acceptance gates

- **I-2 · Minecraft:** One game lock covers cooperating lifecycle commands. `send`, `console`, and `exec` are not read-only. Account for other writers, including direct unit control, timers, and background guest processes. Without evidence of quiescence, do not claim an offline-consistent archive. No-replace publication does not prevent the game UID from changing archives separately. Preflight failures leave service state unchanged. Back up a confirmed inactive server without starting it or its container. Refuse unknown, failed, and transitional states. For a running server, verify the guest unit's clean stop. Archive only `survival/` as the game UID, validate compression and expected world members, and read them back in a mock restore. Test same-second and concurrent runs without changing existing archives. A failed write, failed validation, conflict, or uncertain publication after stopping leaves the unit stopped. Resume a previously running unit only after confirmed publication. If restart fails, report archive success and service failure separately and exit unsuccessfully. The archive is server data, not declarative configuration or a backup of credentials or Tailscale identity.
- **I-1 · Parsec:** Keep `writeBoundary` ordering, the XWayland launcher, declared config content, the order of unrelated mapping rows, exactly one row for the declared controller ID, and mode `0600`. Create a missing file with `PublishNew`. For an existing file, account for symlinks, read errors, and writers before `ReplaceOwned`. File-wide config authority does not give file-wide mapping authority. Leave the old fixed temp name and unrelated entries untouched. If replacement is unsafe, preserve data and report how to resolve the conflict. A design that makes ordinary activation fail unconditionally is not ready.
- **I-3 · Home:** Keep `check --require-noop` read-only: no-op exits `0`, pending exits `2`, and conflict or error exits unsuccessfully. Treat no-replace move, symlink repair, and reference rewrite separately. Preserve the declared backup policy for both Bun and npm. If required replacement cannot exclude other writers, refuse the whole batch before the first move. App-stop probes and rechecks do not prove exclusion. Keep same-filesystem moves and explicit collision handling. Do not copy and delete across filesystems or merge into existing data. Interrupt fixtures at intent, rename, backup flush, publication, parent flush, and completion. Compare source, destination, and backup with journal records, without logging reference contents. Document any durability limits for newly created parent and journal directories.
- **I-4 · Build-result roots:** Keep eligibility and exact user confirmation if unlink remains. Require evidence that competing project writers cannot substitute a leaf between inspection and unlink. A parent descriptor does not provide a conditional unlink by inode. Without that evidence, stop at a read-only proposal. Test with isolated links and mocked roots, never with real GC.

If a new writer or counterexample defeats a required guarantee, stop that branch and resolve the contract or the ownership boundary before proceeding. Independent branches need not stop. A narrower policy that changes an existing success case needs explicit compatibility review and a recovery path.

## Verification and limits

For 2a, run `python3 scripts/ci/check_docs.py` and `git diff --check`. Later PRs keep the [existing CI baseline](../../.github/workflows/nix-validation.yml), including the three always-on checks, framework tests, host derivation evaluation, and trust-boundary checks. Register new focused checks with their implementation in `checks.x86_64-linux`, the [selector](../../scripts/ci/select-checks.py), and its tests. Core changes select all affected consumers. Feature changes select their own checks. Docs alone add no feature check, and an unknown diff base selects all focused checks. Do not add a full flake check to the PR gate.

Run cases against the shipped form. The migration runner ships with its Python adapter and core. The cleaner ships a single Python file, the OpenCode hook ships a substituted single TypeScript file, and the framework CLI ships a directory. A sibling import that resolves only in the checkout does not pass packaging verification. Fixture reports identify the tested revision, command, expected and observed outcomes, and untested conditions.

Source review, evaluation, packaged fixtures, VM tests, and host acceptance are [different evidence](../memory/evidence.md). A mocked flush sequence is not a power-loss test. A mocked service stop cannot prove exclusion of live writers. Host acceptance needs separate approval and a dated receipt with the host, generation, outcome, and recovery evidence. No PR here authorizes merging, host switch or boot, ordinary Home Manager activation, real HOME migration, service stop or backup, GC, credential or sharing changes, data relocation, or paid adoption.

**Rollback:** Revert 2a, research changes, and unused cores in Git. After separate consumer activation, a Git revert does not undo persistent state. Reconcile final archives and stages before restoring from an independent backup. Reconcile Home's journal, source, destination, and backup before an operator chooses what to restore. Git cannot restore collected store paths. The original closeout was PR #59. The later convergence review uses pinned implementation PRs and repository checks, with their landing and host acceptance tracked separately.

## Historical closeout and retained gates

| Scope | What to reconfirm after the prerequisite merges and retarget |
| --- | --- |
| I-4 | [`review-results`](../cookbook/nix-store-clean.md#what-the-audit-means) lists and shortlists links only. Same-UID project writers do not share an exclusion protocol. Neither a fresh root list nor a parent descriptor makes unlink conditional on the inspected inode. Keep native pruning and GC separately confirmed. Do not restore the old unlink behavior as a rollback. |
| 2h · [#55](https://github.com/tenzyu/nixfiles/pull/55) | Approve the [Parsec compatibility change](../../assets/parsec-activation/README.md#compatibility-review-gate). Only missing files are seeded. Existing differing config bytes, missing or differing controller rows, and wrong modes warn and leave the files untouched. A warning does not mean that activation applied the declaration. |
| 2l · [#56](https://github.com/tenzyu/nixfiles/pull/56) | Approve the [Home migration limits](../../assets/home-layout/README.md). Unsupported repairs, including an existing Bun alias that needs retargeting or a Codex reference that needs rewriting, block the entire `apply` before it writes. `check` only reports. Keep supported no-replace moves and use the journal to reconcile interrupted work before retrying. |
| 2g · [#57](https://github.com/tenzyu/nixfiles/pull/57) | Keep the packaged restore and failure fixtures separate from [runtime acceptance](../../modules/50-features/game-servers/_internal/minecraft-backup/README.md#verification). The default fixture mocks lifecycle and UID transition. The separate namespace fixture uses real `setpriv` but inert managers. Neither proves live clean stop, recovery, or absence of bypass writers. |
| 2j · not adopted | [Research #58](https://github.com/tenzyu/nixfiles/pull/58) supports the decision to keep pinned `nix-minecraft` and the local 2g backup. Adopt no candidate code. Keep the native container and Tailscale setup and make no sharing changes. Do not open a composition PR for this decision. |

The [packaged interoperability fixture](../../assets/safety/python/README.md) checks Linux `flock` contention on one inode and regular-file no-replace publication in both publisher orders. Home locks the HOME directory inode, not Shell's `.safety.lock`. The Parsec adapter shares only the native flush helper, not Shell's named-stage lock protocol. The Python core has no shared lock API, and neither core offers conditional replacement or unlink of an existing inode. TypeScript is process-only here. The [Rust demo](../../tools/adr02-rust/README.md) tests lookup and descriptor lifetime only. Neither earns a lock or publication pass. No other wrapper or consumer needs that API added: leave ARK and Rust game scripts, the Serve route, and trust boundaries in their existing scope.

Keep the [protected-branch selector](../../scripts/ci/test_select_checks.py) tests with the packaged checks. Runtime Shell changes select the game and interoperability checks, and the shared native helper also selects Parsec. Runtime Python changes select Home migration. The game layout, operator, and package select Minecraft; flake manifest and lock changes select all focused checks. Local Markdown adds no focused checks except the explicit Shell fixture contract. Re-run the combined checks, framework suite, and `neko5`, `neko6`, and `neko7` derivation evaluations after retargeting. Use landed relative paths or already-reachable pins for source links, and PR numbers for review receipts, so links survive squash merges.

This closeout does not cover native GC or staged-boot and rollback in a VM, real Home Manager activation, live Minecraft operations, or acceptance on any host filesystem. The fixtures do not prove power-loss durability or support on untested filesystems, mounts, or kernels. CI time and host closure deltas are unmeasured: there is no matching runner/cache baseline or comparable realized host output pair in this validation. The Rust demo's opt-in build receipt is not a host closure measurement.

## Convergence decisions

**Reviewed main** was [`9638f84d5b5e8f2de1de4af401f0bbb1cd35d707`](https://github.com/tenzyu/nixfiles/commit/9638f84d5b5e8f2de1de4af401f0bbb1cd35d707). PRs #48–#59 had landed and each had a passing focused GitHub check. The only later change after #59 was [#62](https://github.com/tenzyu/nixfiles/pull/62), scoped to the neko7 serial console and its regression test.

This documentation PR targets an integration branch built from that main revision. It depends on the following code PRs, all targeting main at review time. Their outcomes describe the combined review tree. After the code PRs land, rebase the documentation-only commit onto main and confirm the same source blobs and focused checks before landing this decision record.

| Dependency | Reviewed head | Disposition |
| --- | --- | --- |
| [#65 Home Migration](https://github.com/tenzyu/nixfiles/pull/65) | `a48fc51567ddc2030e55c6b77a3d2fa89f77b5f0` | Actionable pending warning and strict conflict boundary |
| [#64 Parsec](https://github.com/tenzyu/nixfiles/pull/64) | `8629b14888ca831affde39d0f298f979a3bd6e33` | Application-owned native settings and controller mapping with review |
| [#63 Minecraft](https://github.com/tenzyu/nixfiles/pull/63) | `a55c502aac0f623a651e872248a32c83766051b9` | Retained job guard and explicit recovery |
| **Integration base** | `19052959d17abdf08285f8c74efa2d322ec19dc4` | Combined code under review. No host selections changed. |

### Home Migration

- **Activation.** The generated activation runs `check --activation` before native `checkLinkTargets` and `writeBoundary`. Pending moves or manual repairs emit the operation, owner, source, destination and remediation. A two-sided data collision, an unsafe plan, or a managed-file blocker has a failing status. Native Home Manager still checks current generation link conflicts. `check --require-noop` remains available for a caller that wants exit 2 for an actionable plan. The isolated DAG fixture executed both actual pre-write steps, reached a fixture write-boundary marker after a pending warning, and stopped before that marker for an unmanaged current link target. [Activation declaration](../../modules/50-features/home/home-migration.nix) · [Fixture](../../assets/home-layout/test-activation.sh)
- **Authority and ownership.** App-specific rules stay with their owner. AndroidMic declares its rule and variables beside the adb wrapper, gated by the app and optional XDG layout. The existing storage profile remains the owner of path settings for tools outside individual package selections, including Codex on neko5, where the repo Codex package is disabled. A disabled owner contributes no rule. A missing legacy path requires no move even if a new path already exists. [Rules and operator runbook](../../assets/home-layout/README.md)
- **Mixed data.** The Bun/npm `onConflict = "backup"` exception is superseded. Any two populated paths block apply and preserve both entries. Manual check can report an apparent match of supported regular files and directories after comparing the full tree, bytes, type, UID, GID, mode, mtime and xattrs. Links, unreadable entries, special files, mount crossings and detected changes prevent claiming equivalence. Apparent equality cannot authorize mutation. Reconcile deliberately, preserve the unused copy and recheck. The separate scaffolding exception requires enabled generation link destinations, recognized store links and plain owned directories. Explicit apply rechecks and journals the scaffold into a no-clobber archive path before the separate legacy rename. The HOME inode lock covers participating migration runs. It cannot exclude app writers or stop a parent rename. A corrupt or partial journal cannot establish prior completion. [Planner and commit adapter](../../assets/home-layout/migrate.py) · [Recovery](../../assets/home-layout/README.md#中断後の照合)

### Q5 — Bun and Codex references

Native `BUN_INSTALL_CACHE_DIR` and `BUN_INSTALL` direct future writes. Bun projects may have symlinks into the global store. Reinstalling affected projects against the selected cache is a practical alternative when their inputs and offline requirements permit it. Preserve the original cache and verify external references before choosing that path. For Codex, `CODEX_HOME` chooses where it loads configuration and hooks. Project-local configuration can remove some machine-specific paths, but the variable cannot change arbitrary absolute paths already recorded in JSON, TOML, or shell commands. A universal launcher or compatibility link would retain dependency on the legacy name and would cover only participating callers. Keep the per-file operator review, preserve the originals, and refuse a batch requiring any existing link or file replacement before creating state. Revisit an automated operation only with a native app migration or demonstrated ownership and writer exclusion for the selected leaves. [Bun cache](https://bun.sh/docs/pm/global-cache) · [Bun global store](https://bun.sh/docs/pm/global-store) · [Codex configuration](https://learn.chatgpt.com/docs/config-file/config-basic) · [Codex hooks](https://learn.chatgpt.com/docs/hooks) · [Manual repair cases](../../assets/home-layout/README.md#既存リンクと参照の修復)

The [2k research](0002-home-migration-research.md) remains the dated baseline for alternatives. Antidot's overwrite/copy fallback and incomplete recovery violate the move contract. boxxy redirects only callers using its enclosure. xdg-ninja remains an optional diagnostic. Native Home Manager owns generation links. This review adopts no OSS files or new dependencies.

### Parsec

The original source records the four decoder, VSync and overlay values but no bug or benchmark for each one. A latency preference is an inference. The Dynabook touchpad's false controller and the read-only store-link write failure are recorded. Keep the SDL/XWayland workaround and the `06cb,83d7` row pending live acceptance. The [runbook](../../assets/parsec-activation/README.md#why-these-settings-exist) links the original module and vendor guidance.

Parsec 150-89 and later imports legacy `config.txt` assignments into its own JSON. A check for JSON absence followed by publishing a text seed has a cross-leaf race and could import Nix values into a concurrently created app file. Seed the four values directly in the documented `config.json` shape and let Parsec retain legacy import authority. When legacy input already exists, skip the JSON seed and guide the operator through review. A competing JSON writer wins the same-leaf no-replace check. The independent mapping seed only fills an absent `gpmap.txt`. Existing mappings and settings are preserved even when expected values differ. The read-only `parsec-activation-review` reports the intended keys, pending legacy assignments and expected controller row without exposing actual unrelated values. Use Parsec's settings or a deliberate, backed-up edit with writer control and then verify effective settings in the app. [Parsec import and native configuration](https://support.parsec.app/hc/en-us/articles/32381346632596-Accessing-Your-Advanced-Settings) · [Review procedure](../../assets/parsec-activation/README.md#review-an-existing-installation)

Both seeds run after `writeBoundary`, use the native dry-run path, and publish a verified private `0600` stage without replacement. A parent descriptor refers to the selected inode even if renamed. The two seeds and saved-file observations are independent. Confirm observed files after `OutcomeUnknown` before retrying.

### Q7 — Minecraft admission and recovery

**Keep `minecraft.lock.job`.** systemd 260.5 enqueues a job before the D-Bus method reply. The synchronous client waits for that job's removal, and a disconnect can fail the wait. Service jobs can remain after clients disappear. An empty current queue, a missing client PID, and the current unit state cannot establish how an earlier request ended. `--no-block` returns at admission, `--job-mode=fail` only restricts queue conflicts, and freeze or job cancellation cannot establish a clean save and stop. A new transient coordinator would still need to fence existing host and guest entry points. [Manager enqueue](https://github.com/systemd/systemd/blob/v260.5/src/core/dbus-unit.c#L1985-L2010) · [Client wait](https://github.com/systemd/systemd/blob/v260.5/src/shared/bus-wait-for-jobs.c#L48-L78) · [Service job lifetime](https://github.com/systemd/systemd/blob/v260.5/src/core/job.c#L1465-L1476) · [Alternatives and recovery](../../modules/50-features/game-servers/_internal/minecraft-backup/README.md#diagnose-and-recover)

The existing flock is on the tmpfiles inode for the boot and survives through the managed waiter and configured-UID writer. The root-only guard fences subsequent managed mutations if a request remains unconfirmed after the flock becomes free. `game diagnose minecraft` can inspect the guard, both managers and queues without taking the mutation lock or changing state. An authorized operator reconciles the prior request and any possible effects with both managers and journals, holding the original flock before clearing the empty guard. Reopening admission does not start the server. After archive creation, validation, publication, or confirmation fails following a stop, recovery is explicit and the operation never issues a restart. A visible final after failed sync or observation is `OutcomeUnknown`. Preserve it and verify it before considering recovery; service recovery is a distinct outcome.

The packaged fixture restores newly generated archive data and exercises failures, retries, competing operations, lost replies and hard termination with inert managers. The namespace test changes to actual UID/GID 27009 with `setpriv` and still uses inert managers. The native units and writer IDs, backup retention, persistent data, and Tailscale sharing keep their existing ownership. ARK and Rust remain disabled on neko7. Sharing backup or lifecycle code requires game-specific evidence for a clean save, storage, concurrent updaters and restore. The [2i research](0002-game-server-research.md) supports keeping pinned `nix-minecraft` and the local operator instead of another tool or control plane.

### Q8 — Safety Core and Rust

**Keep Python for Home Migration.** Rust's `OwnedFd` provides lifetime enforcement. The opt-in `openat2` demo establishes bounded lookup and follows the opened directory inode across renames. `NO_XDEV` from `/` would reject existing supported layouts, and the demo's `O_PATH` descriptors cannot be used for flock or fsync. A Rust consumer would need authorized mount anchors, sync-capable descriptors, and `renameat_with(NOREPLACE)`. The existing Python consumer already uses no-replace rename with pinned parent descriptors. Neither implementation makes the source pathname a compare-and-swap or gives application writer exclusion. Rust panic handling and descriptor drop cannot resolve SIGKILL, power loss or an uncertain rename. A native helper would introduce descriptor transfer and a second failure channel after commit. The opt-in Rust demonstration has a pinned test receipt outside host closures. No host closure or comparable CI cost reduction was measured. Keep it as a maintained fixture and design reference. Reopen a port only for a demonstrated Python-boundary defect with a Rust design that reduces it, a complete fixture and packaging parity plan, staged rollout, and a rollback compatible with prior journals. [Rust demonstration](../../tools/adr02-rust/README.md) · [Linux openat2](https://man7.org/linux/man-pages/man2/openat2.2.html) · [Linux rename](https://man7.org/linux/man-pages/man2/rename.2.html)

| Layer | Contract and actual consumer |
| --- | --- |
| Python | Home owns manifest authority, diagnostics, HOME-inode lock and journal. `MoveNew` attempts a same-mount no-replace rename, then syncs the destination and distinct source parents. The selected directory descriptors live through those calls. The operation preserves the moved inode, with no assertion that the original pathname still names the opened parent or that a racing source entry still matches plan. A failed sync or confirmation can leave a visible rename. Inspection of real entries and the journal drives recovery. [Python operations](../../assets/safety/python/README.md) |
| Shell | The Minecraft writer uses the private `PublishNew` contract with a trusted stage, exclusion for compliant writers, file flush, no-replace link and final parent flush. Archive validity, lifecycle and operator authorization remain consumer responsibilities. The Linux interoperability fixture exercises same-inode flock and Shell/Python regular-file publication in both orders. It cannot establish common application locks or a guarantee against bypass writers. [Shell contract](../../fixtures/contracts/safety-shell.md) |
| Parsec | The same publication contract applies to the private `O_TMPFILE` adapter. It shares the existing descriptor flush helper, and has a different stage lifetime and no shared admission lock. The named-stage Shell operations require a trusted entry and participants that Parsec cannot establish. [Publication limits](../../assets/parsec-activation/README.md#publication-boundary) |
| TypeScript / Nix | Keep argv/exit/redaction inside the packaged framework CLI and the approval gate, event environment and bounds inside OpenCode's single substituted hook. They have different packaging and authority and no shared filesystem consumer. Native Nix types, DAG edges, systemd and tmpfiles supply their own guarantees. Do not add a process SDK, cross-language RPC or another transaction layer. [CLI packaging](../../modules/10-foundations/framework-tools.nix) · [OpenCode hook packaging](../../modules/50-features/development/opencode-direnv.nix) |

### Convergence verification and rollback

Run the three always-on Nix checks plus the selector's Home, Parsec and Minecraft checks. The integrated review also exercises the previously landed Shell, Python, OpenCode and result-cleaner checks. `nix run -L .#framework-test` verifies the 63 Nix unit tests, adapter invariants, feature projections and the migration DAG. `bash assets/home-layout/test-activation.sh` runs the evaluated pre-write migration and native link check against a disposable HOME. Home's filesystem suite includes real Linux moves and contention, alongside injected ENOSPC, sync and journal failures. One packaged user-xattr fixture skips when the sandbox does not support those attributes. The unprivileged local suite exercises the real xattr difference. The separate Rust demo builds with a locked toolchain (three tests). Neither the Rust fixture nor mixed fixture backends establish a host closure or CI timing delta.

The reviewed commands and GitHub runs are attached to [#65](https://github.com/tenzyu/nixfiles/pull/65), [#64](https://github.com/tenzyu/nixfiles/pull/64), and [#63](https://github.com/tenzyu/nixfiles/pull/63). Re-run the selected checks, all three host derivation evaluations, doc and retrieval checks, and `git diff --check` when retargeting this documentation PR. The [Dreaming manifest](../memory/provenance.json) records selected exact source blobs so the same bytes can be verified across squash merges.

Power-loss durability, hostile same-UID writers, untested filesystems and systemd builds, live service and app behavior, current user data, and host-generation rollback remain outside this evidence. **Real-host acceptance NOT RUN** for Home Manager, Parsec, and Minecraft. A Git rollback can remove the new diagnostics or declarations. It cannot reverse a data rename, establish archive publication, or restore a previously changed app setting. Use the [Home journal recovery](../../assets/home-layout/README.md#中断後の照合), [Parsec review](../../assets/parsec-activation/README.md#review-an-existing-installation), and [Minecraft admission and recovery](../../modules/50-features/game-servers/_internal/minecraft-backup/README.md#diagnose-and-recover). Native GC, staged boot and restore acceptance remain separate work.
