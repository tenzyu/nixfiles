---
type: Reference
title: Evidence hierarchy for Nix and deployed systems
description: Decide what a claim proves and preserve the revision, environment and failure identity.
status: stable
source_revision: 438aa02b426db0a5962dd0102f0cbb04a5191c06
sources:
  - id: hosts
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/00-hosts/neko7/configuration.nix
    title: Declared host features
  - id: ci
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/.github/workflows/nix-validation.yml
    title: Focused CI gates
---

# Evidence is not interchangeable

| Claim | Minimal proof | Cannot establish |
| --- | --- | --- |
| **SOURCE** (declared) | Exact commit, path, feature/option and guard | Evaluates or runs |
| **EVALUATED** | Host/system and successful `nix eval` exit | Built or activated |
| **BUILT** | Exact derivation, output and build receipt | Booted runtime |
| **TESTED** | Fixture or VM, command, expected/actual, tested revision | Physical host acceptance unless actually tested |
| **OBSERVED** | Host, boot/generation, timestamp, unit/process/output receipt | Tomorrow's state or an unrelated host |
| **INFERRED/UNKNOWN** | Hypothesis, uncertainty and discriminating observation | A success or authorization |

Keep the failed run's identity after a later fix. Selecting `sops-nix` in source does not prove that an age key or decrypted secret exists. A past Minecraft login does not prove current service health. An accepted PR does not grant runtime access.

When correcting a claim, identify the earlier claim and source IDs, the contradictory evidence, what it supersedes, remaining uncertainty and the exact evidence for the new scope. Never mark `verified: human:...` for an agent-authored result. The [configuration decisions](decisions.md) define operational limits. The [knowledge maintenance procedure](dreaming.md) describes how to update records.
