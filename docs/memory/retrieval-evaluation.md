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

The valid pair below used fresh contexts and the same fixed eight-command budget. Failed commands counted toward the limit.

## 2026-11-20 valid pair

Functional commit `bda99416d6a0faf8ab2f01ce4a507e77246a74b5`, tree `d4966f7283a5e286241c15cc6c57d8fee7aecf48`. Trial docs `75baed0bc533d959079b06ddaec6d90eedb3e76b`, overlay tree `6a55ba24e566f6b227ec1ab0e0b3bc483111b092`. The common corpus, permissions, model and effort matched. Only the wiki-assisted arm received the startup router and wiki. Separate materialized roots and T3 contexts provided task-level isolation.

Both arms used exactly eight calls and each finished six cases with two partial cases. Neither produced an unsafe promotion or false live acceptance claim. The partial criteria were:

- **#66 provenance.** Both respected the reviewed scope and individual approval, but did not fully specify extracting the docs-only patch from the actual old base and excluding old integration-only product ancestry before retargeting.
- **Semantic memory.** Both covered pinned corrections and blinded grading, but omitted a requirement to prune a genuine duplicate while retaining its provenance.

The wiki-assisted arm added context on cases already answered correctly at the same budget. The pair demonstrated no comparative gain under the acceptance gate. Timing and tokens were not compared. Retain the factual corrections, the duplicate consolidation with its archive link, and the previous validated startup memory. The final docs add this receipt after the trial freeze. [Reviewed source and evidence](../adr/0002-invariant-safety.md#convergence-decisions).

## 2026-11-20 narrow rerun

The scoped pair used functional commit `bfbfbe28afb9f2771bfafac20334a2cccd906593`, tree `7ff5c8ac7ff05d2b30020cce82a5aed530dbc0b7`, trial docs `482f47aaa136f7ddb9756ec1a412fd232cf1bed0` and overlay tree `03d31a6ce97db52403b6e6429f9056f4491eb1fb`. The two existing Sol Medium readers reused their provider and effort settings with fresh contexts, identical copied primary inputs and a four-command budget that included failures. The wiki-assisted arm also received the frozen router, index and decision page. The evaluation history and log pages were outside both input sets.

Both arms used exactly four calls and met both reopened cases.

| Case | Applicability on the replacement source |
| --- | --- |
| 4 · Interrupted Home migration | Both preserved the copies and journal, required a separately approved offline window, reconciled journal entries with observed paths, preflighted the whole group before resuming, and kept equal-copy retirement separate. The replacement adds ordinary apply and rollback recovery fixtures that refuse a changed later member while preserving pending paths and journal bytes. |
| 7 · osu! measurement | Both distinguished batched observer reads from event timing, left intervals and dispatch unknown when clock selection failed, required a window-to-output match for foreground eligibility, and omitted missing scanout from the DSO and tearing denominators. Independent monitor observations remain visible. |

The formatted PipeWire replay has separate offline evidence. The other six cases were outside this rerun. The original eight-case inputs, scores and no-gain result remain as recorded above. This scoped result establishes applicability to the repaired source for the two reopened cases. Timing, tokens and broader improvement remain unmeasured. [Exact Home fixtures](https://github.com/tenzyu/nixfiles/blob/2ecf45de6781f9e6fa9018018e4732e8a9d2f34d/assets/home-layout/test_migrate.py#L641-L695) · [Exact lab analyzer](https://github.com/tenzyu/nixfiles/blob/245f266e6b614f4ca4f6132c8ed59fd6f51ef715/scripts/osu-performance/osu-lab.py).

## 2026-11-20 capacity follow-up

Functional commit `25a70b30c6deaa0236148b882e6eca5e7707ea9d`, tree `ef892b2463c82914ce899b6328a4eeecfea5ee07`, pins Home `e5b62b445ecf4bcabc5ece88c8723d1a730b5bbb`. The capacity repair changes case 4's evidence. Fresh plans and recovery sum bytes by destination mount for copies still needing a stage, and check each copy again just before staging. The new fixture distinguishes a ready earlier stage from later copies that still need capacity. On refusal, the stage, published entries and journal remain intact.

Case 7's evidence carries forward on the identical L commit `245f266e6b614f4ca4f6132c8ed59fd6f51ef715`. The original eight-case result and the four-call two-case result retain their frozen scores, budgets and inputs. At this freeze, the informational confirmation of case 4 alone had yet to run. [Capacity regression](https://github.com/tenzyu/nixfiles/blob/e5b62b445ecf4bcabc5ece88c8723d1a730b5bbb/assets/home-layout/test_migrate.py#L355-L423).
