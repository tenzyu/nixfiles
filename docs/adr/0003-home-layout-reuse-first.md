# ADR-0003 — Make HOME unremarkable: native-first, repairable state

- **Status:** Accepted **maintenance direction** (2026-11-23); implementation cleanup is **not yet accepted**.
- **Scope:** Future HOME/layout work on neko5 and neko7. This ADR changes the product goal, **not** the currently deployed state or the safety guarantees of existing migration code.
- **Provenance:** The reuse-first survey was selectively carried over from [archived PR #78](https://github.com/tenzyu/nixfiles/pull/78). The stricter HOME Authority v1.1 problem statement and the failed admission evidence remain historical research in [PR #79](https://github.com/tenzyu/nixfiles/pull/79). They are not a mandate to implement physical-HOME enforcement.
- **Objective:** The user should **not have to think about HOME** during ordinary use. Minimize recurring operator intervention, novel mechanisms, surprises after upgrades, and unrecoverable loss; do not maximize purity of directory names.

## Decision: stop pursuing these guarantees in the everyday configuration

| Abandon as a HOME-maintenance requirement | Why / accepted consequence |
| --- | --- |
| A globally immutable physical HOME object graph against arbitrary normal-UID processes, including held file descriptors and shared mappings | Conflicts with ordinary application writes and generation activation; a VFS/LSM-scale enforcement problem is not justified by cosmetic cleanliness. Normal applications may modify their own data. |
| Universal removal or denial of legacy dotpaths in all mount/user namespaces | Unsupported applications may create legacy entries. Their presence is **drift to observe**, not a security incident or a reason to block login/switch. |
| One globally enforced mutable backing for all unwrapped clients and pre-existing handles | A declared native path applies only where the application and process environment honor it. A stale writer remains a migration risk. |
| Automatic migration, merging, or reconciliation of arbitrary live application state on every NixOS/Home Manager switch | Neither XDG nor Home Manager establishes ownership or writer exclusion for arbitrary app state. Existing data stays put absent a separate, reviewed migration. |
| A new authority daemon, universal wrapper, independent journal/state engine, or per-app routing DSL merely to keep HOME tidy | More code, activation hooks and failure modes would create the maintenance burden this decision is intended to eliminate. |

These are **explicitly abandoned product requirements**, not claims that the Linux security boundary can never be implemented. Security isolation for a specific risky application remains a separate, scoped problem. The [v1.1 evidence run](https://github.com/tenzyu/nixfiles/actions/runs/45106709624) collected valid JSON and exposed 19/19 successful nested mutation attempts; **CI Green meant evidence collection succeeded, not enforcement**. The experimental branch is archived, not promoted.

## Delegate to established owners

| Responsibility | Primary owner | Hard limit / failure boundary |
| --- | --- | --- |
| System generation, service activation, rollback | **NixOS**, systemd, `nh` as a frontend | Generation rollback does **not** revert user data, secrets, external state or application databases. |
| User configuration, native application options, generated links and activation ordering | **Home Manager** | HM collision checks cover managed entries, not arbitrary running-app state. Do not use `force` or backup overwrite to conceal a conflict. |
| Conventional app state destinations | **XDG Base Directory** and each application's **documented native option/environment** | A convention is not a mandatory write-policy; existing files are not relocated by exporting a variable. |
| Opportunistic HOME clutter discovery | **`xdg-ninja --skip-unsupported`** on demand | Advisory inventory, not a list of safe deletions and not proof of the actual live state root. |
| One-off supervised same-filesystem relocation, only when worth doing | **GNU Coreutils `mv`** after verified backup, quiescence and destination inspection | `mv -T --no-copy --update=none-fail` is a no-copy/no-replace building block, **not** a transaction protocol. Test its availability on the target host and never assume concurrent writers are excluded. |
| Service-scoped process isolation | **systemd** sandbox options; optionally established app wrappers when a concrete need is demonstrated | Not host-global HOME authority. Do not deploy boxxy, mittens, bubblewrap or new namespaces solely for dotfile aesthetics. |
| Backup and restore | An **established backup tool** (Restic is a candidate), plus a tested restore procedure | A tool recommendation is not evidence that backups, timers, credentials or actual restores exist on neko5/neko7. Verify before relying on them. |
| Ephemeral/persistent storage topology | **preservation / impermanence**, only for an explicit ephemeral-root requirement | Not a default and not a substitute for app-native XDG paths. Avoid a second owner of HM-managed links (hjem/smfh). |

Reuse-first references carried over from #78: [Home Manager dotfiles](https://nix-community.github.io/home-manager/usage/dotfiles.html), [GNU Coreutils `mv`](https://www.gnu.org/software/coreutils/manual/html_node/mv-invocation.html), [boxxy module](https://github.com/nix-community/home-manager/blob/master/modules/programs/boxxy.nix), [antidot MovePath](https://github.com/doron-cohen/antidot/blob/master/internal/utils/files.go). Antidot's copy/delete fallback does not meet a strict no-copy migration boundary; this ADR does **not** select it as the mover.

## What nixfiles itself must own

1. **Policy:** Declare each selected application's supported native settings using the existing typed host/user feature interface and normal NixOS/HM options. Preserve explicitly documented exceptions; notably HM-owned `~/.zshenv` may be required to bootstrap `ZDOTDIR`. Do **not** invent a separate authority DSL.
2. **Observation and verification:** Evaluate configuration and run existing focused CI checks; use `xdg-ninja` and app-native read/write/relaunch checks only for a **specific, observed** issue. Classify `configured`, `built`, `activated`, `runtime verified` separately. Unknown or merely reported host state remains unknown.
3. **Human-controlled exception and recovery:** For a necessary one-time move, identify the incumbent, active writers, both source and target, backup/restore evidence, and rollback path. Stop and report conflicts, rather than reconciling or deleting them automatically. Prefer an upstream/app-native import/export before filesystem-level moves.
4. **Maintenance budget:** For HOME cleanliness alone, introduce **zero new permanent services, wrappers, private format parsers or activation-time migrations**. If a future concrete problem requires custom code, document the failing native workflow, owning layer, exit conditions and removal strategy in a separate ADR/PR.

A tolerable legacy entry is cheaper than a universal process-interposition system. Maintain **data safety, reproducible declarations and recovery**, not universal pathname purity.

## Transitional reality on main — do not silently remove safeguards

As of this decision, `main` **still includes** the accepted `home-migration` / `home-layout` mechanism, its pre-switch admission logic, journal and Python runner; see [ADR-0002](0002-invariant-safety.md), [rollout runbook](../cookbook/home-migration-rollout.md), and [Home migration README](../../assets/home-layout/README.md). That existing mechanism and its historical tests are real source, not evidence of successful host deployment. This ADR **does not disable, simplify, replace, or certify it**.

Its eventual retirement is a distinct, reviewed implementation change, not part of this documentation-only cherry-pick. Until then:
- Keep current holding/adopted routes, conservative refusal behavior, and recovery records intact.
- Do not remove journals, bypass `check --admission`, or weaken collision/unknown-result safeguards merely because the long-term direction is simpler.
- Do not conflate a successful `nh os switch` with successful data migration or rollback of mutable state.
- Prefer **no new migration work** unless the user experiences a concrete functional problem or explicitly approves a one-time relocation.

## Practical acceptance and rejection gates

| Future change | Pass | Reject / pause |
| --- | --- | --- |
| Native option or app-path adjustment | Evaluation matches the intended host, no unrequested side effects, and affected application confirms read → write → restart against its intended data | Surprise credential/session loss, a competing populated root, unsupported option, or unseen active writer |
| Home Manager / NixOS generation change | Focused checks pass; the affected two-generation switch/rollback is tested in a disposable VM when behavior changes; independently verify real-host runtime **before** claiming it works | Tests skipped/errored, or rollback would strand mutable data |
| Backup and migration | Actual recoverable backup and restored sample; source/target inspected; writer exclusion and a specific rollback plan | Collision, incomplete inventory, unproven restore, cross-filesystem surprise or unknown live writer |
| Cleanliness audit | Read-only, on demand, actionable diagnosis; no impact on normal launches | Blocking logins, new always-on reconciler, auto-deleting dotpaths or forcing sandbox wrappers |
| Removal of legacy `home-migration` code | Separate PR demonstrates an explicit safety-preserving replacement or proven non-use, with CI and runtime acceptance scope stated | Loss of current refusal/recovery behavior, silent data movement, or assumed host adoption |

**This PR only changes documentation.** It does not change a host's declaration, deploy software, move files, close a data migration, or authorize a real switch.
