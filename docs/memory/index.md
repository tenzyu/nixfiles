---
okf_version: "0.2"
---

# LLM Wiki — source-bound lookup

Select **one** relevant concept, then follow its primary evidence. This OKF bundle is not a transcript dump, a parallel feature registry or a declaration that a host is healthy. [Cookbook](../cookbook/index.md) is the separate human-operation interface.

## Understand design

- [Architecture](architecture.md) — flake-parts, typed host seed and native module boundaries.
- [Feature ownership](feature-options.md) — where NixOS, Home Manager and integration effects belong.
- [Composition](composition.md) — pure value stages versus native NixOS priority and merge.
- [Host boundaries](host-state.md) — current source selections versus dated observations.
- [Decisions](decisions.md) — durable constraints, rejected alternatives and acceptance gates.

## Recover or correct knowledge

- [Evidence](evidence.md) — how to distinguish Git, evaluation, a test, a build and a deployed host.
- [Dreaming](dreaming.md) — reconstruct, correct, preserve provenance and stop when useful.
- [Retrieval evaluation](retrieval-evaluation.md) — answer tests and search-only versus Wiki-plus-search protocol.
- [Update log](log.md) — dated corrections, not current runtime authority.

The semantic map must remain much smaller than the underlying source. Source changes trigger a **proposal to revisit the affected page**, not permission to rewrite evidence or activate a machine. [Dependency scanner](../../scripts/ci/wiki_scan.py).
