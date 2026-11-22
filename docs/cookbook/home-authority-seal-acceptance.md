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
and staged two-generation activation can satisfy it. The fixture currently
exercises the ordering/activation phase within one VM generation; **a second
real system-generation rollback test is still required** for full certification.
