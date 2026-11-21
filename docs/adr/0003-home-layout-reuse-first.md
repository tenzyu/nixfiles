# ADR-0003 — Reuse existing tools before implementing HOME migration

**Status:** proposed, unmerged; **date:** 2026-11-21. This is a design checkpoint, **not** an executable migration or authorization to switch hosts. The currently installed Python migration hooks remain active on `main` until a validated replacement is separately accepted.

## Decision

Do **not** replace the old Python HOME migration engine with a newly written Rust CLI. No missing capability has been established that requires an independently maintained mover, manifest format, journal, state reconciler, or sandbox. Instead, reuse each tool only inside its proven contract:

| Responsibility | Reuse | Contract / limit |
| --- | --- | --- |
| Canonical paths and application configuration | Home Manager native options, XDG and supported environment variables | Declarative destination; **does not migrate already-populated mutable application state** |
| Managed file collision handling | Home Manager `checkLinkTargets` and supported backup options | Applies to Home Manager-owned links/files, **not to all runtime state**; never enable `force` or backup overwrite to rescue a migration |
| Discovery and advice | `xdg-ninja --skip-unsupported` | Observation, not proof of which copy a live process reads or writes |
| Optional interactive rules | `antidot clean` | Upstream `MovePath` falls back from rename to copy+delete; do **not** adopt as a strict no-copy migration engine for credentials or active data |
| Optional per-process path compatibility | Home Manager `programs.boxxy`, `mittens` for supported agent harnesses | Only wrapped commands and descendants; no guarantee for unwrapped T3, GUI, systemd services or new processes outside the wrapper |
| Optional application confinement | `bubblewrap`, Bubblejail, NixPak or `necessary-nu/sandbox` | Use only for a demonstrated per-app need; namespaces do not themselves relocate existing state |
| Persistent-storage topology | Preservation / impermanence | Appropriate when an ephemeral-root design is actually required; not a substitute for app-specific XDG settings |
| Declarative file deployment alternatives | Hjem / smfh | Can manage deployed files, but replacing Home Manager would introduce a second owner of HOME entries |
| One-time no-clobber move | **Existing GNU Coreutils `mv`** | `mv -T --no-copy --update=none-fail -- SOURCE DEST` refuses occupied target and does not copy across devices; it requires stopped writers and checked parent directories |

Primary evidence: [Home Manager collision documentation](https://nix-community.github.io/home-manager/usage/dotfiles.html), [GNU Coreutils mv documentation](https://www.gnu.org/software/coreutils/manual/html_node/mv-invocation.html), [antidot MovePath](https://github.com/doron-cohen/antidot/blob/master/internal/utils/files.go), [mittens README](https://github.com/fj/mittens), [Home Manager boxxy module](https://github.com/nix-community/home-manager/blob/master/modules/programs/boxxy.nix).

## Observed neko7 inventory (2026-11-21)

The operator supplied `xdg-ninja --skip-unsupported` output. These are **reported paths only**; whether each is the sole authoritative state and whether its destination already exists are unverified.

| Group | Observed legacy | Proposed destination | Native variable / mechanism |
| --- | --- | --- | --- |
| pi | `~/.pi` | `~/.config/pi` | `PI_CODING_AGENT_DIR=~/.config/pi/agent` (note the nested `agent` directory) |
| Docker | `~/.docker` | `~/.config/docker` | `DOCKER_CONFIG` |
| CUDA | `~/.nv` | `~/.cache/nv` | `CUDA_CACHE_PATH` |
| less | `~/.lesshst` | `~/.local/state/lesshst` | Native XDG history on less ≥ 598; otherwise `LESSHISTFILE` |
| Codex | `~/.codex` | `~/.local/share/codex` | `CODEX_HOME` (contains credentials, session data and configuration) |
| Bash | `~/.bash_history` | `~/.local/state/bash/history` | `HISTFILE`, create parent and file as required |
| Zsh | `~/.zshenv` | **keep while Home Manager owns it** | Existing `programs.zsh.dotDir` intentionally publishes the bootstrap `~/.zshenv` to set `ZDOTDIR` |

Do not treat the XDG-ninja Zsh diagnostic as permission to remove a Home Manager-managed startup file. Confirm with `readlink ~/.zshenv` and the evaluated `programs.zsh.dotDir`.

## Existing-tool procedure: inspect → retain incumbent → move once → switch

1. **Inspect only.** Run `xdg-ninja --skip-unsupported`, inspect both locations with `ls -ld` / `stat`, and check actual active shell, user-service and app paths. A directory existing in the target is not proof of successful migration. Save the observed Nix generation and back up both locations independently.
2. **Retain incumbent.** When both old and new locations have data, or a process still writes to the old location, do not change the corresponding native application destination in the next generation. Resolve the conflict offline, using application-native import when offered. No tool should silently pick a newer-looking copy.
3. **Move one resolved group.** Stop all writers, verify the destination is absent and the source is a normal file or directory on the same filesystem. Create only the required destination parent directory. Use GNU Coreutils already in the environment:

   ```sh
   # Example only. Run on the target host after checking backups and closing Docker.
   mkdir -p "$HOME/.config"
   mv -T --no-copy --update=none-fail -- "$HOME/.docker" "$HOME/.config/docker"
   ```

   On a collision, Coreutils exits nonzero without replacing the existing destination. On cross-filesystem rename failure, `--no-copy` prevents fallback copying. No automatic transfer of nested files from both trees, no history merge, no credential overwrite, and no cleanup of old journals is authorized.
4. **Declare and switch.** After confirming the new path contains the authoritative data, select its native variable through Home Manager and perform one reviewed `nh os switch`. Restart affected user services / re-login; verify actual read → write → relaunch and correct state root. Retain backups and the former Nix generation; rolling back configuration does not move data back.

This procedure is intentionally **not** tied to an automatic activation hook. It is a valid no-new-program baseline and exposes the exact amount of glue, if any, that a future automation would need.

## Is any new implementation necessary?

For **one-time XDG relocation of the seven observed neko7 paths**, **no**. The source/target pairs are handled by native options and an existing no-clobber file mover, with manual conflict review. Neither a Rust CLI nor new file lifecycle machinery is justified.

For the *stronger* requested behavior — `nh os switch` automatically inspects arbitrary competing mutable state, skips conflicted groups, persists an actionable report, and later promotes only resolved groups while preserving runtime authority — **some integration is still necessary unless a proven existing tool provides the full contract**. Coreutils handles moves but not orchestration; Home Manager handles declarative links but not app data authority; antidot and mittens have the above scope/overwrite limits. This is a capability gap, not evidence that the gap must be filled with a new executable.

**Gate for further code:** demonstrate failure of the existing-tool workflow on an isolated replica *and* show that no upstream/native integration resolves the actual failure. Then prefer the smallest declarative orchestration around installed commands; propose a standalone Rust component only for an identified syscall-level invariant the installed commands genuinely cannot provide.

## Acceptance / stop conditions

- No migration on production merely because an XDG-ninja rule matches; confirm actual route and backup first.
- A collision must leave both copies intact. Active, unwrapped or long-lived writers invalidate the move assumption.
- Test the installed GNU Coreutils version's `--no-copy` and `--update=none-fail` behavior on a disposable directory before use. Neither the local tool-version check nor Coreutils documentation establishes the exact version on neko7.
- Verify neko7's active Codex/T3 service and credentials, Docker auth, pi history, less/Bash state and new-login environment before considering a path adopted.
- neko5 is not covered by the neko7 observations; do not change its runtime state by inference.
- A fully automatic two-switch implementation, no-conflict guarantee for nonwrapped processes, and actual host acceptance remain **UNVERIFIED**.
