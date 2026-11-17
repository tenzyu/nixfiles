---
type: Reference
title: "Knowledge maintenance"
description: "LLM Wiki Dreaming using OKF v0.2"
status: stable
source_revision: 22191670806242933bc156e4a5e0cd9ad3ea14f1
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/flake.nix
    title: "flake.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/framework/modules/configurations.nix
    title: "framework/modules/configurations.nix"
---

# LLM Wiki / OKF v0.2 maintenance

## Purpose and boundaries

`README.md` is the first-visit interface; `ROADMAP.md` is not-yet-done work. `docs/index.md` is the progressive-disclosure entrypoint for this **source-derived knowledge bundle**. Each concept has YAML frontmatter with at least `type`, and preferably `title`, `description`, provenance `sources`, `status` and `source_revision`. `index.md` and `log.md` are reserved OKF names.

Existing operational manuals stay close to the executable assets where appropriate. Link to them instead of duplicating dangerous or long procedures.

## Evidence model

- **Declaration:** exact Nix/TypeScript/Python code and feature condition.
- **Test observed:** executed command, environment, result and date.
- **Runtime observed:** host, generation, time, process or metric.
- **Hypothesis:** unverified inference or optimization.
- **Blocked:** missing authorization, compatibility, reproducible test or telemetry.

`source_revision` records the Git commit used to derive a concept, not a runtime validation. The optional OKF `verified` property must only be added for a real review or deterministic comparison; never assign `human:` review without human approval. `status: stable` means the article is a usable reference, not a guarantee of live deployment.

## Dreaming workflow

1. From [index](index.md), locate concepts relevant to the changed Nix modules, scripts and host declarations.
2. Compare their immutable source references with changed implementations. **Implementation has priority** for declared behavior. A runtime observation needs its own host/generation evidence.
3. Merge duplicate or contradictory facts into one concept; preserve durable Why/What and causal mechanisms, not an append-only transcript. Keep runbooks for risky How.
4. Mark legacy observations with date and environment. Move uncompleted acceptance work to [ROADMAP](../ROADMAP.md), not the README.
5. Update provenance, crosslinks, index and [log](log.md). Verify Markdown links, YAML frontmatter, feature names and commands before merging.
6. Do not claim Nix builds, VM exercises, reboots or deployment acceptance unless those checks were actually executed.

## References

- [Open Knowledge Format v0.2 specification](https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/main/SPEC.md)
- [LLM Wiki concept](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
