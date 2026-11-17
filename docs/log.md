# Knowledge update log

## 2026-11-18

- [neko7 development runbook](t3code-neko7.md) records the SplitCast regression, clean-clone replay, rollback, observed T3 access and the on-demand Serve declaration. It supersedes the earlier source-only remote-access status for this observation window.

## 2026-11-17

- **Architecture correction (PR #12):** Removed the nested framework Flake; moved projection into `modules/_internal/framework/`, kept `modules/10-fundamental/`, and separated tooling and package overlays. The CLI names and host declaration surface remain unchanged.
- **Feature provenance:** Restricted `feature-trace --feature` to the requested feature and separated evaluated definitions from best-effort text-scan hints.
- **Projection integrity:** Added an assertion for a user-selected feature whose same-named NixOS counterpart is explicitly disabled.
- **Migration safety:** Automatic Home Manager migration now requires an explicit opt-in; pending work otherwise stops activation before mutation.

- **Reconciliation:** Replaced stale README references to removed `modules/10-framework/` and cache-check documents with the current `framework/` layout.
- **Creation:** Added OKF v0.2 knowledge index, architecture, host state, decisions and maintenance rules.
- **Separation:** Placed unmet tasks and acceptance gates in [ROADMAP.md](../ROADMAP.md), independently of current behavior.
- **Preservation:** Existing operational runbooks remain primary for detailed commands and data-loss protections. No host activation or acceptance tests were performed as part of documentation editing.
