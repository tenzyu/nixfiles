# HOME authority independent seal acceptance

This is a **separate, deliberately failing** acceptance test for Draft PR #78.
The successful `home-authority-vm` characterizes bypasses; the new
`home-authority-seal-vm` requires those bypasses to be CLOSED, not reproduced.

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

**Expected baseline (PR #78): FAIL.** The present feature is observe-only,
does not relocate or seal the old backing, and explicitly rejects
`local.homeAuthority.root.enforce = true`. CI failure on this stacked
verification PR is evidence that the requested closure does not yet exist,
not a regression in PR #78's diagnostic check.

There is no expected-failure wrapper, result inversion, silent skip, or
deployment to neko5/neko7. This check stays separate until an actual backend
and staged two-generation activation can satisfy it. The fixture currently
exercises the ordering/activation phase within one VM generation; **a second
real system-generation rollback test is still required** for full certification.
