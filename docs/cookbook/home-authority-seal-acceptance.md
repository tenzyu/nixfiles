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

There is no expected-failure wrapper, result inversion, silent skip, or
deployment to neko5/neko7. This check stays separate until an actual backend
and staged two-generation activation can satisfy it. The fixture currently
exercises the ordering/activation phase within one VM generation; **a second
real system-generation rollback test is still required** for full certification.
