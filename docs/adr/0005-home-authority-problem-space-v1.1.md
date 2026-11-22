# ADR-0005: HOME Authority v1.1 problem-space and CI evidence

Status: **Problem-space accepted; implementation/admission NOT accepted.**
Supersedes ADR-0004's assumption that ordinary writes to a canonical mutable
directory *inside* HOME are compatible with the full contract. ADR-0004 and
Draft PR #78/#79 remain evidence and historical counterexamples, not an
implementation mandate. This ADR does **not** enable any host option.

## Fixed scope

1. **Trusted administrator:** the ordinary user's UID, user services and
   all unknown same-privilege processes are the untrusted writers. The host
   administrator is trusted, but an administrator-initiated transition must
   still exclude untrusted writers for the *entire* admission interval.
2. **Whole-HOME immutability:** every physical object stored at any depth
   below the HOME directory is fixed in a stable generation: names, contents,
   directory entries, symlink text, and security-relevant metadata.
   Access-time noise is not a protected content mutation. Changing any
   protected object requires an explicit trusted transition.
3. **No legacy compatibility view:** forbidden legacy pathnames must not
   resolve in any untrusted user's available mount/path view. A symlink,
   bind mount or private namespace recreating that pathname is not a
   substitute for removal. Stale FDs must not mutate protected objects
   or establish a divergent writable authority.
4. **Per-host local authority:** neko5 and neko7 are independent authorities,
   with no global consensus or cross-host serialized-write requirement.
   Files physically outside HOME may hold mutable state only under an
   independently declared local authority; a symlink physically in HOME has
   immutable link text, but does not automatically freeze the outside target.

## Normative invariants

- **I-1 Fixed object graph.** For each admitted stable generation, the
  HOME-rooted protected inode/name/content/metadata graph is unchanged by
  normal-UID operations, including inherited file/dir FDs and shared mmap.
  A negative errno alone is not sufficient: compare pre/post actual objects.
- **I-2 Authorized transitions.** An administrator may change the protected
  graph through an explicit transition, but untrusted processes cannot
  borrow a temporarily unsealed state, even between separate syscalls.
  Partial failures preserve an identifiable incumbent and do not silently
  overwrite, copy, restore or orphan acknowledged durable writes.
- **I-3 Legacy non-exposure.** After admission, no prohibited legacy pathname
  resolves from any relevant untrusted view, including a user-created
  namespace where available.
- **I-4 One local state authority.** Stale writers cannot commit to a hidden
  independent backing. This requirement is per host, not across hosts.
- **I-5 Lifecycle continuity.** At least two genuine NixOS/Home Manager
  generations, successful switch back, restart/crash recovery, service
  availability and commit continuity must be accepted without relaxing I-1
  through I-4.

A host-administrator with raw write privileges is inside the trust boundary;
its ability to clear FS_IMMUTABLE_FL is **not** a v1.1 security violation.
Allowing an ordinary UID to modify HOME *during* that clearance **is**.

## Disposable CI experiments (Draft PR #79)

| Check | Probes | What a pass means |
| --- | --- | --- |
| home-authority-vm | Prior negative controls | Diagnostic reference only |
| home-authority-seal-vm | Pre-held FDs, direct prohibited root operations, private mount namespace, 20-operation nested object mutation matrix, trusted administrative unseal, deterministic cutover interposition, collisions, cross-device moves, real generation switches and rollback, reboot and repeat matrix | The evidence *was measured and classified*; a green build does **not** mean v1.1 admission |
| home-authority-two-host-vm | Two QEMU nodes with independent local disks/authority state; one crash while the other updates, persistence and root name-denial after restart | Independent fixture behavior; not real neko5/neko7 verification |
| Static host evaluation | Read-only evaluated options for neko5/neko7 | Configuration evidence, not runtime enforcement |

The v1.1 suite also attempts a private legacy compatibility view from an
untrusted user namespace, explicitly distinguishes unavailable userns/mount
capabilities from enforcement, and reruns the mutation matrix after reboot.
The transition suite injects trusted-process crashes at three cutover
boundaries; these are process failures, not physical power loss. A separate
two-node VM test power-cycles one QEMU node while another keeps its independent
state writable. Neither experiment automatically admits a host.

The v1.1 matrix measures create/openat/mkdir/symlink/link/rename/rename
exchange/unlink/rmdir/ordinary and pwrite/append/truncate/ftruncate/
MAP_SHARED mmap/posix_fallocate/chmod/utime/xattr, plus a read control.
It seeds known objects with a *trusted test administrator*, then invokes a
separate UID-1000 process for every mutation and fingerprints the graph
before/after. A successful nested write is a **v1.1 VIOLATION**, even if the
original root-only acceptance oracle passed. Unsupported syscalls and probe
harness errors are reported separately, not counted as security denials.

The previous VM's root-only `chattr +i` fixture keeps descendants mutable.
It is therefore expected to fail v1.1 full-HOME immutability. This
contradiction must not be 'fixed' by changing the oracle or excluding the
canonical subtree: the experiment is intended to expose the mismatch.

Deterministic migration interposition, two-generation activation and
rollback, and the reboot service failure remain **admission blockers**
until proven closed. This experimental PR does not implement a new backend,
remove the `root.enforce` assertion, install anything on either host, or
authorize a merge.

## CI truth model

- **PASS**: the concrete invariant holds for the explicitly exercised
  environment and operations.
- **VIOLATION**: an untrusted write or exposure measurably breaks the
  invariant.
- **BLOCKED**: at least one required condition fails; not eligible to
  enable `root.enforce`.
- **PARTIAL / NOT_TESTED**: the executable suite cannot establish the full
  guarantee, including unknown applications, all namespaces/filesystems,
  real live FDs, power-loss storage durability, and physical-host behavior.
- **ERROR_OR_UNSUPPORTED**: a measurement failed or the required syscall was
  unsupported. This is never recoded as 'DENIED'.

Artifacts are **machine-readable evidence**, not authorization to deploy.
A green CI may legitimately contain v1.1 VIOLATION and BLOCKED gates, since
the purpose of the diagnostic is to establish whether the current proposal
satisfies this stricter contract. A separate fail-closed admission check
would be necessary before enabling enforcement.

## Unresolved scope that CI cannot establish universally

The experiments do not prove all possible interleavings, all user-created
namespaces, a real host's mounted filesystems/active processes, data hidden
outside declared authority roots, or actual physical power loss. These
require a supporting mechanism's formal authority boundary and host-side
read-only inventory before any deployment decision.
