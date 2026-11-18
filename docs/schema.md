---
type: Reference
title: "Dreaming and knowledge maintenance"
description: "Correcting the OKF v0.2 Wiki against the repository"
status: stable
source_revision: 438aa02b426db0a5962dd0102f0cbb04a5191c06
sources:
  - id: flake
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/flake.nix
    title: "Flake entrypoint"
  - id: adapter
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/_internal/configurations/configurations.nix
    title: "Typed configuration adapter"
---

# Dreaming: maintain a small, accurate knowledge map

## Distinct responsibilities

| Layer | Audience | Content |
| --- | --- | --- |
| [README](../README.md) | First-time reader | Purpose, host overview, design, navigation, safe validation |
| [AGENTS](../AGENTS.md) | Assistant at task entry | Fixed constraints, retrieval order, nonnegotiable safety |
| [MEMORY](../MEMORY.md) | Assistant during work | Small current-source index and durable decisions |
| [Wiki](index.md) | Pull-based reference | Conceptual architecture, invariants, operational runbooks and provenance |
| [Roadmap](../ROADMAP.md) | Future work | Unverified acceptance and open migration work |
| [Log](log.md) | History | Dated knowledge corrections, not instructions or runtime proof |

**Do not copy all documents into an agent's initial context.** Retrieve the narrowest topic through the index. The Wiki is not a replacement for code search or current source inspection.

## Source and evidence protocol

1. Identify the task's **What/Why** and locate all relevant code paths in the current Git tree. Use `flake.nix`, `modules/00-hosts/<host>/configuration.nix`, the selected feature, and tests as the first evidence.
2. For each claim, classify it as **declared**, **evaluated**, **tested**, **built**, **observed at host + generation + time**, **hypothesized**, or **blocked**. Do not promote a lower evidence tier to a higher one.
3. Reconcile the old Wiki against implementation. Correct broken paths, outdated feature flags, inaccurate defaults, and duplicate concepts. Where observations disagree with source, preserve them as *dated* observations instead of declaring the current host healthy or broken.
4. Keep one canonical explanation per concept. Link to it from the README/index and leave operational details in runbooks. Preserve rejection reasons and failed acceptance so another agent will not repeat an unsafe experiment.
5. Update navigation and [knowledge log](log.md); validate Markdown relative links, code path existence and source provenance. Stage a documentation-only change unless a separately requested code fix is needed.
6. Store secrets, credentials and host decryption keys **nowhere** in the Wiki or examples. Do not synthesize host output, successful CI, hardware acceptance, or a human approval.

## OKF and provenance

This repository follows the [Open Knowledge Format v0.2 specification](https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/main/SPEC.md): `index.md` and `log.md` are reserved navigation/history pages, and concept pages can carry `type`, `title`, `description`, `status`, `source_revision` and `sources` metadata.

A `source_revision` is the immutable commit **used for source comparison**, not a claim that the machine ran that revision. Each `sources[].resource` must point to an actual file at that revision. Avoid a misleading synthetic `verified: human` field. Update the revision only after reading the corresponding source.

## Why dreaming is useful, and where to stop

[Anthropic's agent memory research](https://www.anthropic.com/research/components-of-agent-memory) describes correcting notes against original evidence, consolidating redundancies and using a Wiki with search for cross-document synthesis. It also reports failure when a Wiki becomes larger than the underlying source material, or when a long always-injected note displaces useful context.

**Convergence rule:** add or change a page only when it reduces lookup cost, fixes a material error, or captures a non-obvious invariant/failed path. Prefer fewer correct links to duplicative pages. Use one targeted source-and-link reconciliation pass rather than regenerating every document after each source commit.
