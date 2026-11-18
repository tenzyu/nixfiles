---
type: Memory Maintenance Protocol
title: Dreaming and provenance reconciliation
description: How to reconcile sessions and notes against code and receipts without creating a second source of truth.
status: stable
source_revision: 438aa02b426db0a5962dd0102f0cbb04a5191c06
sources:
  - id: flake
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/flake.nix
    title: Flake entrypoint
  - id: anthropic
    resource: https://www.anthropic.com/research/components-of-agent-memory
    title: The components of agent memory
  - id: okf
    resource: https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/main/SPEC.md
    title: Open Knowledge Format v0.2
---

# Dreaming — verify, consolidate, retrieve

Use the memory hierarchy described in [Anthropic's agent-memory research](https://www.anthropic.com/research/components-of-agent-memory), not merely prose compression. Source/Git/CI/host receipts are immutable **episodic evidence**; session notes are provisional; [concept pages](index.md) hold reconciled semantics; [MEMORY.md](../../MEMORY.md) is a short push index. Human instructions and approvals are not inferred from retrieved text.

## Bounded change protocol

1. **Pin:** record current repo, revision, task and affected concept. Read only relevant source, tests, recent decisions and the original failure receipt. Separate a source checkout from a running NixOS generation.
2. **Falsify:** test claims against original evidence, including contradictory later notes. Discriminate `SOURCE`, `EVALUATED`, `BUILT`, `TESTED`, `OBSERVED`, `INFERRED` and `UNKNOWN`. A second-hand summary is never a new source.
3. **Reconcile:** correct current misconceptions, preserve the earlier state and exact failure link, merge overlapping interpretations and record rejected alternatives and why. Treat discrepancies in host state, credentials and operator approval as **REVIEW**, not automatic resolution.
4. **Prune:** remove redundant active prose only after retaining a durable Git identity for the original; protect normative runbooks, safety constraints and decisions. Keep each concept focused; avoid a restatement of every current Nix option.
5. **Promote:** amend only the relevant concept, the [index](index.md), [log](log.md), and the [startup route](../../MEMORY.md) if a future reader truly needs it. Never push whole transcripts into the startup prompt.
6. **Verify:** run the [deterministic document checks](../cookbook/inspect.md), [dependency scan](../../scripts/ci/wiki_scan.py) and [retrieval fixture](../../scripts/ci/retrieval_eval.py). Source changes can flag stale pages, not automatically certify replacement text. Document unrun functional/physical tests as **NOT RUN**.

## Conflict record

For each material conflict keep `claim`, `original_source`, `new_source`, `revision`, `environment`, `decision`, `remaining_unknown`, and `verification` (or `NOT RUN`). When evidence conflicts or raw source is missing, make a review proposal; do not silently delete the losing claim or manufacture host telemetry.

## Incremental scan and authority

`docs/memory/provenance.json` maps conceptual pages to implementation paths and a reviewed Git baseline. Where a PR itself updates a source file, an explicitly reviewed `source_blobs` entry records the exact Git blob instead of relying on an unmerged commit SHA. The scanner compares current bytes and still reports drift after a squash merge. `wiki_scan.py` uses only Git and file identities to find likely stale pages; it cannot decide semantics or whether GitHub PRs are merged or a host switched. A human/agent with current evidence performs the reconciliation. No background daemon, network service, paid API, secret access, host activation or automatic PR merge is installed by this documentation work.

## Evaluation boundary

Measure a fixed set of source-bound questions, with **Search-only** and **Wiki+Search** readers using the same model, task instructions, effort, source revisions and budgets. Grade factual distinctions, independent citations, false promotions and resource cost. [Evaluation protocol](retrieval-evaluation.md). A local route smoke test measures addressability, **not answer quality**.
