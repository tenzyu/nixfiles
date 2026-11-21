# ADR-0004 — Physical HOME authority and working-state views

**Status:** investigation; **date:** 2026-11-21. This document specifies the acceptance boundary. No host currently satisfies the complete contract. The new `home-authority` Nix module is a typed **audit and route compiler**, not a filesystem lock.

## The two invariants

1. **One working state.** For each logical application, every authorized consumer (CLI, desktop, login shell, systemd service, spawned agent, restoration job) must open the same authoritative mutable data. A native environment variable, a bind-mounted compatibility path, and an already-open inode are equivalent only when they actually refer to that data and writes remain coherent. Two populated copies with different authority constitute a failure.
2. **One authoritative account root.** For the actual `/home/<user>` (not merely a namespace-visible surrogate), forbidden direct names cannot be created, linked, renamed in, restored, or mutated through a previously opened handle. The enforcement boundary is the file system's namespace and inode semantics. Bypasses outside that boundary—including privileged host processes—must be explicitly modeled.

A complete guarantee across **all** writers and roots is not achieved by an XDG environment variable, Home Manager's link reconciler, an `LD_PRELOAD` hook, one wrapper's mount namespace, or a read-only bind *view*. Some methods do protect a narrower part of the contract; none should be falsely labeled root-wide.

## Existing projects: verified mechanisms and limits

| Existing project | Actual upstream Nix/API | Appropriate layer | Reason not used as the whole solution |
| --- | --- | --- | --- |
| [Home Manager](https://nix-community.github.io/home-manager/usage/dotfiles.html) | `programs.*`, `home.sessionVariables`, `systemd.user.sessionVariables`, `home.file`, `lib.hm.dag` | Native app configuration and generated links | It cannot revoke or unify unmanaged mutable application state |
| [boxxy](https://nix-community.github.io/home-manager/options/home-manager/programs/boxxy.html) | `programs.boxxy.enable` and typed `programs.boxxy.rules` | Opt-in legacy view for **explicitly wrapped** programs | Outside the wrapper, direct path writes still happen |
| [mittens](https://github.com/fj/mittens) | `mittens harness:<name>` (Claude/Opencode/pi), bwrap-based private mount namespace | A more complete per-agent launch view | Automatic relocate/merge and exit-time copy-back have concurrency limits; T3 unwrapped invocation is not covered |
| [preservation](https://nix-community.github.io/preservation/configuration-options.html) | `preservation.preserveAt.<path>.users.<user>.directories`, `how = "bindmount"` | Boot-time persistent source backing for whole application trees | Does **not** make physical HOME immutable or seal stale FDs |
| [impermanence](https://github.com/nix-community/impermanence) | `environment.persistence` (NixOS), `home.persistence` (HM) | Persistent bind mount / symlink for ephemeral roots | It assumes an intentional ephemeral-root topology and does not intercept all writers |
| [hjem + smfh](https://github.com/feel-co/hjem) | `hjem.users.<user>.files`, `xdg.config.files`; JSON manifest linker with generation handling | Alternative to HM for *managed files* | A second owner of `~/.config` links is unnecessary without first migrating HM ownership |
| [antidot](https://github.com/doron-cohen/antidot/blob/master/internal/utils/files.go) | Rule-driven migration + exports; `MovePath` | Interactive migration reference | Rename failure falls back to copy+delete; conflict handling is not a global authority protocol |
| [necessary-nu/sandbox](https://github.com/necessary-nu/sandbox) | `--bind`, mount namespaces, optional `--close-fds`, Landlock | Harden a **known process tree** and close inherited FDs | Launcher-level protection, not all arbitrary host processes |
| [Bubblejail / NixPak](https://github.com/igo95862/bubblejail) | App confinement profiles, bubblewrap | Desktop app isolation when per-app policy is justified | Cannot install a physical-HOME-wide invariant just by defining a wrapper |
| [libetc](https://ordiluc.net/fs/libetc/) | `LD_PRELOAD=libetc.so` intercepts selected path operations | Historical technique | Interposition is bypassed by other libc paths, direct syscalls, static executables or pre-opened FDs |

Comparable NixOS repositories: [preservation's user-level example](https://github.com/nix-community/preservation/blob/main/docs/src/examples.md) keeps `.config/syncthing`, `.local/state`, and other directories on a persistent backing and configures parent ownership using `systemd.tmpfiles`; [TGuimbert's dotfiles](https://github.com/TGuimbert/dotfiles) uses tmpfs `/` with persistent Btrfs volumes. These demonstrate explicit **storage backing**, not a complete write-authority proof. [pperanich/dotfiles](https://github.com/pperanich/dotfiles) is a relevant dendritic `flake.modules.{nixos,homeManager}` composition reference, not a verified root-protection implementation.

## Why a physical-root policy is distinct

`chattr +i /home/<user>` may prevent direct directory entry modification when the filesystem supports it. However `chattr(1)` explicitly warns that immutable attributes do not revoke writes through already open file descriptors. The attribute can also block Home Manager generation link updates. A per-view read-only bind only protects the mount view, while the original writable mount or pre-existing descriptor may still exist. [Kernel / chattr notes](https://man7.org/linux/man-pages/man1/chattr.1.html) and [libmount documentation](https://www.man7.org/linux/man-pages/man8/mount.8.html).

For true acceptance, a candidate must prove **quiescence of old writers**, stable inodes through relocation and rollback, a host-global root policy applied *before* unauthorized user processes start, legitimate NixOS/HM activation under the policy, and an explicit policy for privileged/host namespace escape. Merely checking `ls ~/.pi` after login does not establish these properties.

## Nix API introduced in this PR

`flake.modules.homeManager.home-authority` declares `local.homeAuthority.states.<name>` with:

- `legacy`: exactly one direct dot-entry name.
- `canonical`: absolute one-state destination under the same HOME.
- `mode = "observe" | "native" | "boxxy"`: an explicit rollout decision; **not** evidence of root protection.
- `nativeEnvironment`: generated via `home.sessionVariables` and `systemd.user.sessionVariables` when `native`.
- `kind = "directory" | "file"`: mapped to upstream `programs.boxxy.rules.*.mode` when `boxxy`.
- `root.forbidden`: expected forbidden *physical* directory-entry names.
- `root.enforce`: currently impossible to set true; Nix assertion rejects it until a real proven backend exists.

The module statically rejects duplicate exported variable names, non-dot legacy names, destinations outside the user HOME, and unpaired forbidden names. A native route cutover refuses to activate if the old path still exists or the new root is absent; it does **not** move data. Audit uses standard `test`/`printf`, reports read-only source/target status and next steps, and stores the report at `$XDG_STATE_HOME/nixfiles/home-authority-report.txt` (default `~/.local/state/nixfiles/home-authority-report.txt`) with a private umask. This report is not an authority journal and does not mutate app state. The existing `xdg-ninja` is available for supplemental discovery. No Python or Rust helper is introduced.

Both neko5 and neko7 select the feature in **observe** mode. The six reported neko7 candidates are declared but neither environment variables nor root permissions are mutated by these declarations. The `~/.zshenv` generated by Home Manager for `ZDOTDIR` is explicitly exempt from false pollution classification.

## Missing implementation to satisfy acceptance

The following must be demonstrated in a disposable NixOS VM before any real HOME write denial:

1. **Physical authority fixture.** Create a writable legacy root and a canonical target, hold directory and file FDs open, then attempt `creat`, `renameat2`, `linkat`, restoration and writes through the old descriptors after sealing. Reject any arrangement in which the old backing remains a separate writer.
2. **Activation fixture.** Perform two real NixOS + Home Manager generations under that physical policy, including zsh bootstrap, Nix profile links, user-service relaunch and rollback. No temporary writable window may be exposed to uncontrolled processes.
3. **Visibility fixture.** Exercise native shell, GUI, rootless Docker, systemd user services and T3/Codex sessions. Assert equality of backing inode and read/write visibility where expected; test a deliberately unwrapped negative control.
4. **Host adoption.** Detect both source/target populated state, retain the incumbent without overwriting, and report the smallest operator action; only move data under a verified writer-exclusion boundary. Do not silently bypass Nix user state by creating a second HOME owner.

Until those tests pass, `root.enforce = false` remains truthful. This is a deliberate refusal to certify an unenforced contract, **not** a relaxation of the requested invariants.
