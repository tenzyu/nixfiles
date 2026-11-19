# Knowledge update log

## 2026-11-19

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
- **Migration safety:** Automatic Home Manager migration now requires an explicit opt-in; pending work otherwise stops activation before mutation.

- **Reconciliation:** Replaced stale README references to removed `modules/10-framework/` and cache-check documents with the current `framework/` layout.
- **Creation:** Added OKF v0.2 knowledge index, architecture, host state, decisions and maintenance rules.
- **Separation:** Placed unmet tasks and acceptance gates in [ROADMAP.md](../../ROADMAP.md), independently of current behavior.
- **Preservation:** Existing operational runbooks remain primary for detailed commands and data-loss protections. No host activation or acceptance tests were performed as part of documentation editing.
