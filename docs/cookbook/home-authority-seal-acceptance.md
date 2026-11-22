# HOME authority independent seal acceptance

This is a **separate, fail-closed** acceptance test for Draft PR #78.
The successful `home-authority-vm` characterizes bypasses; the
`home-authority-seal-vm` requires those bypasses to be CLOSED, not reproduced.
The original unsealed fixture failed with 17 actual violations in
[CI #44941728764](https://github.com/tenzyu/nixfiles/actions/runs/44941728764).
The same independent oracle passed with a fixture-only seal service in
[CI #44942386766](https://github.com/tenzyu/nixfiles/actions/runs/44942386766).

Run on a disposable NixOS VM only:

```sh
nix build -L .#checks.x86_64-linux.home-authority-seal-vm
```

A green outcome requires all of the following:

- A `Type=notify` process holds physical HOME dirfd, legacy dirfd and legacy
  writable file FD **before** Home Manager activation, with ordering proved
  by systemd and an explicit readiness barrier.
- After activation, no forbidden root entry remains or can be created by
  `open`, `openat`, `renameat2`, `linkat`, `symlinkat` or copy/restore.
- An old writable FD must either fail with an explicit access error or remain
  coherent with the **same canonical backing**. Successful hidden/orphan
  writes are failures, not successes. A stale HOME dirfd must not create a
  forbidden direct HOME entry.
- Both a normal unwrapped fixture-user process and another mount namespace
  must fail to create forbidden entries in the **physical** HOME.
- The canonical location remains writable by its authorized owner. Denial
  from wrong UID, a broken mount, `ENOENT`, `EEXIST` or unsupported syscalls
  is never accepted as security enforcement.
- The probes exercise an isolated user account, not root's override powers.
  Privileged-host escape and real host rollout remain additional acceptance
  gates; this check cannot certify them.

**Result: PASS in the disposable fixture, but not a production guarantee.**
The fixture-only root-owned service runs after Home Manager activation,
checks that the competing canonical directory is empty, and uses a
same-filesystem Coreutils rename to relocate the incumbent inode without
invalidating any pre-opened directory/file FD. Then `chattr +i` makes the
**physical HOME inode** reject direct entry creation. Old FDs remain open:
their writes either address the same authoritative canonical backing or a
prohibited direct operation is denied. Neither the verifier nor its syscall
checks were weakened, inverted or skipped.

The actual `local.homeAuthority.root.enforce` remains **false on hosts**.
The fixture is not an installable or safely upgradeable host backend; the
immutable physical HOME would currently prevent future Home Manager link
updates. A production design still needs an exclusive and provably
writer-safe generation-switch path and appropriate policies for privileged
host processes. An empty target, controlled startup order, and filesystem
support for `chattr +i` are explicit prerequisites for this particular VM
proof. No production HOME is changed.

## Transition negative controls

A second **disposable backing** under `/home/fixture-transition` measures
the migration boundary separately from the live sealed fixture:

- Deterministic interposition of an unwrapped UID-1000 writer between
  `rename` and `chattr +i`. It recreates the legacy entry on a distinct
  inode while the original canonical tree remains intact. This is an
  **expected, explicitly reported GAP**, not a race-condition PASS.
- Destination collision with both trees populated. GNU `mv -T --no-copy
  --update=none-fail` must fail without overwriting either source or target.
- Different `st_dev` filesystems (`/home` and `/run`): the same move
  must fail without copying or deleting source state. Missing cross-device
  topology fails the test, not silently skipping it.

These observations are included in `home-authority-evidence.json` under
`transition`; the production admission result remains BLOCKED until a
provably excluded-writer cutover removes the interposition gap.

## Measured generation and restart gaps

The expanded [CI #44985524761](https://github.com/tenzyu/nixfiles/actions/runs/44985524761)
used an ext4 Linux 6.18.63 fixture. Both genuine
`switch-to-configuration test` operations returned status **4**:
the next generation could not create `.hm-generation-two`, and rollback
could not recreate `.hm-baseline` under `chattr +i`.
After reboot, the immutable flag, canonical data and canonical write path
survived, but the Home Manager unit was `ActiveState=failed`,
`Result=exit-code`. The root-unseal and interposition gaps were likewise
reproduced. These are **blocking observations**, not an unexpected CI
regression to waive.

The initial report accidentally landed in `/build` and was not included
in the Nix derivation; the artifact export step therefore failed. The
fixture now writes to `$out` explicitly. The readiness calculation requires
actual success of both system switches, managed link appearance, unit
results, reboot persistence and the direct syscall matrix rerun after reboot.
One successful syscall batch cannot mask a failed Home Manager lifecycle.
The [final CI #44986156842](https://github.com/tenzyu/nixfiles/actions/runs/44986156842)
at `cd9031d` **succeeded**: the independent seal oracle and actual VM
evidence export both completed, while the report explicitly records
`two_generation_managed_links=BLOCKED`,
`reboot_services=BLOCKED`, `transition_writer_exclusion=BLOCKED`,
`privileged_physical_root=BLOCKED`, and
`production_enforce=BLOCKED`. The uploaded
`home-authority-vm-evidence` Actions artifact (ID `14739244772`)
contains the structured VM and static host-evaluation JSON. This is a
validated evidence-pipeline result, **not** production readiness.


### Additional v1.1 negative controls

The [v1.1 contract](../adr/0005-home-authority-problem-space-v1.1.md)
requires immutable content and metadata **at every depth** beneath the
physical HOME; root-only new-name denial is insufficient. The new
`v11-mutation-probes.py` seeds an isolated canonical subtree through a trusted
test-only administrator and executes 20 operations as UID 1000, comparing the
actual object graph before and after. It covers existing-file writes,
`pwrite`, append, truncate, `ftruncate`, `MAP_SHARED` mmap, fallocate,
`chmod`, timestamp and xattr edits; new names, links, rename/exchange,
unlink and rmdir; plus a read-only control. Each result is reported as
`VIOLATION`, `DENIED`, `READ_OK`, or `ERROR_OR_UNSUPPORTED`.

A separate namespace probe attempts `unshare --user --map-root-user --mount`
as the unprivileged account, followed by a private bind mount that exposes
`~/.legacy`. If user namespaces or the bind mount are unavailable, the
result remains `UNAVAILABLE_OR_DENIED`: **never** a universal non-exposure
proof. The matrix runs both before and after a real VM reboot.

The transition fixture now also terminates a trusted process immediately
*before rename*, *after rename* and *after seal*. It inspects incumbent
inode/data survival and whether a normal UID can recreate the legacy name
after the process exit. These are deterministic process-death failpoints,
not a simulation of controller power loss or disk cache loss.

`home-authority-two-host-vm` boots independent alpha and beta QEMU nodes,
constructs separate HOME and external state, forcibly crashes alpha while
beta continues its local updates, and checks recovery of alpha's fsynced
state and immutable-root denial after restart. This checks the *lack of a
cross-host authority requirement*, not real host adoption or user session
behavior.

Run the independently scoped suites:

```sh
nix build -L .#checks.x86_64-linux.home-authority-seal-vm
nix build -L .#checks.x86_64-linux.home-authority-two-host-vm
```

GitHub Actions exports one artifact, `home-authority-vm-evidence`, containing
`home-authority-evidence.json` (original oracle + v1.1 matrix and gates),
`home-authority-two-host-evidence.json` (independent-node experiment), and
`home-authority-host-evaluated.json` (static host configuration only).

**Do not interpret CI Green as v1.1 admission.** The old test explicitly
requires writing to an existing subtree *inside* HOME, which v1.1 forbids.
A clean diagnostic run may correctly report many `VIOLATION` and `BLOCKED`
results. Only the evidence's independent v1.1 admission gates describe the
new problem space, and `root.enforce = true` remains disabled on both hosts.

## Full-lifecycle evidence collection

The same VM test additionally creates two distinct *real* NixOS/HM system
generations: initial Home Manager root link `.hm-baseline`, and a
`specialisation.next` which adds `.hm-generation-two`. After proving all
original root-denial/FD invariants, it attempts the actual
`switch-to-configuration test` to generation two, observes the managed
link and systemd unit results, switches back, and reboots the same VM disk.
The test does not unseal to rescue Home Manager activation.
The pre-activation FD witness reopens the *canonical* inode after a legitimate
completed seal, and the seal oneshot accepts only an already-immutable physical
HOME with the verified canonical incumbent. This removes an artificial
restart failure from the fixture without relaxing a single syscall denial.
A missing immutable flag or competing populated root still fails closed.

The test records the following independently of its PASS/FAIL syscall oracle:

- Kernel version, physical HOME filesystem + source + mount flags, mount
  namespace, immutable flags, owner and canonical inode.
- Privileged actor's `chattr -i` capability followed by a real unwrapped
  user process creating a forbidden root entry during the maintenance window.
  Cleanup and resealing are required.
- Generation-one and generation-two system store references, switch/rollback
  exit codes, new managed-link existence, systemd results and canonical data.
- Post-reboot immutable flag, canonical data survival, legacy name absence,
  held-FD witness unit, Home Manager unit and sealing service status.
- Machine-readable gate map: `vm_stale_fd_and_namespace`, generation link
  transition, privileged boundary, reboot service evidence and production
  readiness. There is no synthetic "all-good" result.

CI artifact: `home-authority-vm-evidence.json` from the Nix test output
directory, published as `home-authority-vm-evidence` (30 days). The
workflow validates its JSON schema and requires an explicit
`production_enforce = BLOCKED` until real host authorization exists.
The JSON report is intended to be reviewed even when the VM's
original syscall oracle remains PASS.

**Scope limitations:** This disposable VM cannot establish neko5/neko7
filesystem behavior, credential-bearing T3/Codex sessions, live Docker
storage writers, desktop sessions or host-administrator restraint. Additional
negative controls are required for any new privileged-switch architecture.
A Green CI is **not** permission to set `root.enforce = true`.

There is no expected-failure wrapper, result inversion, silent skip, or
deployment to neko5/neko7. This check stays separate until an actual backend
and staged two-generation activation can satisfy it. The fixture **has
attempted** a real second NixOS specialisation and rollback, both of which
failed (exit status 4) under the immutable HOME policy. A **successful,
writer-safe two-generation switch and rollback** is still required for
certification.
