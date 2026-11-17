# Knowledge update log

## 2026-11-17

- **Foundations consolidation (PR):** Moved the local feature framework and flake-parts fundamentals under `foundations/`, preserving the framework input and CLI interface.
- **Feature provenance:** Restricted `feature-trace --feature` to the requested feature and separated evaluated definitions from best-effort text-scan hints.
- **Projection integrity:** Added an assertion for a user-selected feature whose same-named NixOS counterpart is explicitly disabled.
- **Migration safety:** Automatic Home Manager migration now requires an explicit opt-in; pending work otherwise stops activation before mutation.

- **Reconciliation:** Replaced stale README references to removed `modules/10-framework/` and cache-check documents with the current `framework/` layout.
- **Creation:** Added OKF v0.2 knowledge index, architecture, host state, decisions and maintenance rules.
- **Separation:** Placed unmet tasks and acceptance gates in [ROADMAP.md](../ROADMAP.md), independently of current behavior.
- **Preservation:** Existing operational runbooks remain primary for detailed commands and data-loss protections. No host activation or acceptance tests were performed as part of documentation editing.
