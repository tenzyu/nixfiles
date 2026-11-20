---
type: Testing Protocol
title: Memory retrieval evaluation
description: Controlled search-only and Wiki-plus-search reader comparison with source-bound grading.
status: stable
sources:
  - id: questions
    resource: ../../scripts/ci/fixtures/retrieval-cases.json
    title: Pinned nixfiles retrieval questions
  - id: anthropic
    resource: https://www.anthropic.com/research/components-of-agent-memory
    title: Agent memory study
---

# Does the Wiki improve retrieval?

`python3 scripts/ci/retrieval_eval.py --smoke` validates that each question's expected Wiki route and independent source exist and that the route is discoverable from [index](index.md). It is a **deterministic navigation smoke test**, not an LLM answer benchmark.

For a genuine paired trial: run two fresh agents with **identical model, effort, question set, checked-out Git revision and total tool budget**. Arm S may search Git/source/tests/receipts but must not inspect `MEMORY.md` or `docs/memory/`. Arm W additionally gets the tiny [startup capsule](../../MEMORY.md) and the [concept index](index.md). Both may read implementation and current CI; neither sees the evaluator fixture, answers, grading rubric, or the other's response. Select questions before either reader starts. Allow abstention and forbid writes, network side effects and host contact.

For each question score **one factual point** only if all material distinctions are present, and **one evidence point** only if a path + revision or recorded receipt substantiates them. Count false claims of deployed/runtime acceptance and violations of safety gates separately. Record shell/tool invocations, repeated searches, duration and tokens **only when observed**. Report each response and missed criterion, not just the mean. Do not assert a general quality improvement from one trial or use deterministic smoke coverage as a substitute for this experiment.

The fixture is kept at `scripts/ci/fixtures/retrieval-cases.json` **outside the Wiki search corpus** to reduce answer leakage. Questions concern typed feature contracts, native module semantics, actual host selections, system state versions, the historical Minecraft cutover, SplitCast's ownership and authorization limits. [Evidence](evidence.md) defines allowed claim levels.

## 2026-11-20 pilot

The first blinded pair used functional commit `056076293a10118d34fc2be764c562f39b4840e3` and docs draft `2ddaa5452b73f3ecc703689de72767e89cb5050b`. The source-only reader used nine commands against an eight-command budget. The wiki-assisted reader used eight. The pair is invalid and supplies no measured retrieval benefit.

The rerun is pending on the [replacement functional snapshot](../adr/0002-invariant-safety.md#convergence-decisions) and its exact docs overlay. Both readers must stop after the eighth command. Failed commands count toward the limit.
