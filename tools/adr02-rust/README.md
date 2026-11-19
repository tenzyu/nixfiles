# ADR-0002 Linux directory boundary demo

`open_descendant` borrows an already authorized directory descriptor and returns an owned descriptor for a child directory. The caller chooses and authorizes the starting directory. The demo uses one `openat2` call with `BENEATH | NO_SYMLINKS | NO_XDEV` and returns an `O_PATH | O_DIRECTORY | O_CLOEXEC` handle. The path must be relative, with nonempty components other than `.` and `..`. The kernel confines resolution to the starting descriptor, rejects symlinks (including magic links), and rejects mount crossings (including bind mounts). These guarantees apply during lookup. The descriptor continues to name its directory if that directory or an ancestor moves. [ADR-0002](../../docs/adr/0002-invariant-safety.md), [openat2(2)](https://man7.org/linux/man-pages/man2/openat2.2.html), [open(2)](https://man7.org/linux/man-pages/man2/open.2.html).

`ENOSYS` returns `Unsupported` with the original errno. Symlinks, non-directories, and mount crossings return `Denied` with the kernel errno. Other lookup failures, including `EPERM`, retain their errno. Every failed lookup returns immediately. A non-Linux target fails to compile with an explicit diagnostic.

## Library choice

- **`OwnedFd` with `rustix` 1.1.6.** The standard library manages descriptor lifetime. `rustix` supplies the typed Linux syscall and explicit resolution flags. This keeps the required kernel policy visible at the call site and gives the demo a single direct dependency. [OwnedFd](https://doc.rust-lang.org/std/os/fd/struct.OwnedFd.html), [rustix `openat2`](https://docs.rs/rustix/1.1.6/rustix/fs/fn.openat2.html).
- **`cap-std` 4.0.3.** `Dir` owns a directory handle and offers a larger, portable API for relative filesystem operations. Its Linux open path uses `BENEATH | NO_MAGICLINKS` and can fall back to a manual walk when the syscall is unavailable. Its `rename` permits replacement. That API fits a caller that wants its portable policy. This fixture requires explicit no-symlink and no-mount flags and refusal when the kernel operation is unavailable, so it uses `rustix` directly. [Dir API](https://github.com/bytecodealliance/cap-std/blob/b7acf8e8807fe3fab991884d2208b7e03d35a409/cap-std/src/fs/dir.rs), [Linux open implementation](https://github.com/bytecodealliance/cap-std/blob/b7acf8e8807fe3fab991884d2208b7e03d35a409/cap-primitives/src/rustix/linux/fs/open_impl.rs).

## Run the isolated fixture

From the repository root on Linux, use the `nixpkgs` input in the repository's flake lock. With sandboxing enabled, the offline build uses the vendored checksums from `Cargo.lock` and runs `cargo build` and `cargo test` with `--locked --offline`. The opt-in output is an empty test marker with no runtime references. The crate has no host, flake output, or CI registration.

```sh
adr02_nix='let
  pkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  demo = pkgs.callPackage ./tools/adr02-rust {};
in'

# One-time input provisioning, if the pinned inputs are absent locally.
nix build -L --no-link --builders '' --impure \
  --expr "$adr02_nix demo.nativeBuildInputs ++ [ pkgs.stdenv demo.cargoDeps ]"

# Build and test using only locally available inputs.
nix build -L --offline --no-link --builders '' --impure --expr "$adr02_nix demo"
```

On 2026-11-19, Cargo and rustc 1.95.0 from nixpkgs `f68407657ad294471eb4b2e65d193df26edf729f` built and passed all three fixtures on x86_64 Linux 6.18.63. Input provisioning needed the binary cache for the cold compiler and linker (612.2 MiB estimated download) and the locked crate sources (3.8 MiB downloaded). After provisioning, the offline dry run selected only the demo derivation. The logged release build and test compilation took about five seconds combined.

| `BOUNDARY-01` fixture | Observed result |
| --- | --- |
| Open a child after the authorized root is moved and its old name reused. Drop the original descriptor and open a grandchild. | The target device and inode match the moved tree. The resulting descriptor is close-on-exec. |
| Try absolute, traversal, empty, dot, and malformed paths. Try a symlink or regular file as a leaf and as a parent. | Lexical inputs are rejected. Kernel lookups retain `ELOOP` or `ENOTDIR`. |
| Inject `ENOSYS`, `EXDEV`, and `EPERM` at the syscall boundary against a valid child path. | The fixture verifies the full flag mask and checks error classification, original errno, and unchanged directory entries. |

The `ENOSYS` and `EXDEV` observations are injected. A legacy kernel and a live mount crossing remain untested. This fixture exercises directory lookup and descriptor lifetime. Publication, replacement, locking, crash durability, and host acceptance require separate evidence. Any later consumer must establish that holding authority to a moved tree is acceptable for its operation.
