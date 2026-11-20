# Knowledge update log

## 2026-11-20

- **ADR-0002 candidate.** The user's accepted design replaces the warning-only Home route with per-group continuity and an embedded write gate. [D2](decisions.md#d2--data-and-rollback-safety) is the canonical rule for equal-looking roots and independent retirement authority. The repeated ADR statement and its older scaffold evidence remain in the [archived draft](https://github.com/tenzyu/nixfiles/blob/af0cc75d74353079ea550f3cd90548ea41dc6812/docs/adr/0002-invariant-safety.md#L210).
- **Parsec source route.** The old main pin leads to the legacy text seeder. The [candidate Parsec route](../adr/0002-invariant-safety.md#parsec) points to native JSON seeding and read-only review at the exact candidate revision. [Superseded decisions page](https://github.com/tenzyu/nixfiles/blob/af0cc75d74353079ea550f3cd90548ea41dc6812/docs/memory/decisions.md).
- **Evidence scope.** The [six-delta candidate](../adr/0002-invariant-safety.md#convergence-decisions) and source blobs replace the 2026-11-19 integration snapshot for candidate lookup. The earlier [Home review](../adr/0002-invariant-safety.md#home-migration) failed whole-group retained-source recovery. The independent check of the earlier published repair passed the packaged engine and VM cases. The replacement H/L pins add ordinary apply and rollback resume preflight, account-scoped admission, validated PipeWire replay and linked display eligibility. Maintained combined checks and disposable Firefox and adb route checks passed. AndroidMic evidence reaches the FHS derivation. R4's completed 2026-11-20 **FAIL** at Home `2ecf45d` covered aggregate staging capacity during group resume. The repair at `e5b62b4` on `25a70b3` passed the targeted regression, direct and VM fixtures and R4's dated scoped capacity recheck. Earlier combined and route receipts retain their original scope. The standalone #65 selector gate awaits #67. Host acceptance **NOT RUN**.
- **Paired evaluation.** The invalid pilot remains in history. The [valid eight-case pair](retrieval-evaluation.md#2026-11-20-valid-pair) demonstrated no comparative gain on its frozen inputs. Both arms met the two reopened cases at four calls each in the [narrow rerun](retrieval-evaluation.md#2026-11-20-narrow-rerun). Those results retain their frozen scope. Case 7's evidence carries forward on exact L. Both arms met the informational [case 4 confirmation](retrieval-evaluation.md#2026-11-20-capacity-follow-up) at four calls each on the capacity-follow-up trial overlay. Retained the factual corrections, duplicate consolidation and previous validated startup memory.
- **Provenance audit.** The embedded materializer adds activation admission while preserving typed feature projection and native priority. The CI workflow still supplies scoped build, evaluation and test evidence. Updated those reviewed blobs only. The older neko7 declaration drift remains open. [Manifest](provenance.json).

## 2026-11-19

- **ADR-0002 convergence:** Reconciled the prior abort-on-pending policy, Bun/npm backup exception, Parsec import behavior, and Minecraft's uncertain-job guard with the reviewed implementations in PRs #63–#65. This describes the [2026-11-19 review snapshot](https://github.com/tenzyu/nixfiles/blob/af0cc75d74353079ea550f3cd90548ea41dc6812/docs/adr/0002-invariant-safety.md#convergence-decisions). The application and service limits remain operational checks. Real-host acceptance **NOT RUN**.

- **Canonical feature semantics (PR #47):** Project an explicit host `false` into embedded Home Manager without treating an unspecified NixOS user `false` as an explicit HM override. Added adapter and native-priority regression fixtures; `feature-trace` now reports the surviving NixOS option's winning priority and distinguishes source hints. Source and test changes are committed; Nix evaluation, CI and host impact comparison are separate acceptance steps. [Decision](../adr/0001-canonical-feature-semantics.md).

- **Structural Dreaming:** separated source-linked semantic knowledge from operational runbooks; retained legacy documentation paths as redirects. Added a bounded evidence/retrieval contract, deterministic metadata and source drift checks. This is documentation/CI work only, not a host activation or measured reader improvement.


## 2026-11-18

- **Source reconciliation (`438aa02b426d`):**

- **First-visit experience:** rebuilt [README](../../README.md) around explicit host selections, evaluation vs activation, and operational boundaries after comparing more than twenty Nix-heavy dotfiles/NixOS README files.
- **Source correction:** aligned [host inventory](host-state.md) and [game-server features](../cookbook/game-server-features.md) to `neko7`'s selected `game-srv.enable = true` and `/srv/minecraft`; retained the completed generation-68 story as a dated observation instead of calling a historical cutover still pending.
- **Provenance repair:** replaced historical non-existent module source links in [decisions](decisions.md) and [Wiki protocol](dreaming.md) with immutable references to current implementation paths.
- **Retrieval hygiene:** reduced [MEMORY](../../MEMORY.md) to a small source index and expanded [Wiki navigation](../index.md). Source is authoritative for declarations, while recorded host observations remain time-scoped.
- **Documentation-only:** no NixOS activation, credential migration, service restart, OS build or runtime verification was carried out as part of this reconciliation.

- **Earlier entries:**

- [Host inventory](host-state.md) and [feature projection](architecture.md) document explicit host selections, Home Manager Zsh scope and the disabled features.

- [neko7 development runbook](../cookbook/t3code-neko7.md) records the SplitCast regression, clean-clone replay, rollback, observed T3 access and the on-demand Serve declaration. It supersedes the earlier source-only remote-access status for this observation window.

## 2026-11-17

- **Architecture correction (PR #12):** Removed the nested framework Flake; moved projection into `modules/_internal/framework/`, kept `modules/10-fundamental/`, and separated tooling and package overlays. The CLI names and host declaration surface remain unchanged.
- **Feature provenance:** Restricted `feature-trace --feature` to the requested feature and separated evaluated definitions from best-effort text-scan hints.
- **Projection integrity:** Added an assertion for a user-selected feature whose same-named NixOS counterpart is explicitly disabled.
- **Migration safety:** Automatic Home Manager migration now requires an explicit opt-in; pending work otherwise stops activation before mutation. [PR #32 removed activation-time apply on 2026-11-18](https://github.com/tenzyu/nixfiles/commit/b730db76c24928f0d6f5d91d1d6355f71a67ff72). See [D2](decisions.md#d2--data-and-rollback-safety) for the later candidate policy.

- **Reconciliation:** Replaced stale README references to removed `modules/10-framework/` and cache-check documents with the current `framework/` layout.
- **Creation:** Added OKF v0.2 knowledge index, architecture, host state, decisions and maintenance rules.
- **Separation:** Placed unmet tasks and acceptance gates in [ROADMAP.md](../../ROADMAP.md), independently of current behavior.
- **Preservation:** Existing operational runbooks remain primary for detailed commands and data-loss protections. No host activation or acceptance tests were performed as part of documentation editing.
