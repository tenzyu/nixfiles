---
okf_version: "0.2"
---

# nixfiles — documentation map

**Start here only when a task needs more detail than [README](../README.md).** This is a source-grounded, pull-oriented Wiki, not a copy of the Nix files or an agent's event transcript. Source declarations, evaluated output, and live host state are separate evidence levels.

## Understand the system

| Question | Read |
| --- | --- |
| What gets imported, projected and materialized? | [Architecture](architecture.md) |
| Why does an option live in NixOS, Home Manager or an integration? | [Native feature options](feature-options.md) |
| What do the named value/attrset composition helpers guarantee? | [Composition](composition.md) |
| What do the three hosts **declare**, not necessarily run? | [Host inventory](host-state.md) |
| Why are changes gated or deliberately not automated? | [Decisions](decisions.md) |
| How is this Wiki corrected and kept small? | [Dreaming and evidence protocol](schema.md) |

## Operate specific components

| Concern | Runbook or source |
| --- | --- |
| Focused PR checks and CI | [Validation](ci-validation.md) |
| `sops-nix`, age keys, secret handoff and Tailscale | [Secrets and Tailscale](secrets-and-tailscale.md) |
| Selected Minecraft container, disabled ARK/Rust | [Game-server features](game-server-features.md) |
| Historical Minecraft `/srv` migration and rollback | [Storage migration](game-server-srv-migration.md) |
| Persistent game directory / service account invariants | [Service layout](service-layout.md) |
| Nix generation cleanup and GC roots | [Store cleanup](nix-store-clean.md) |
| T3 Code + Tailnet Serve on neko7 | [Development service](t3code-neko7.md) |
| OpenCode / direnv shell context | [OpenCode devShells](opencode-devshells.md) |
| Candidate OpenCode server cutover | [OpenCode migration](opencode-neko7-migration.md) |
| SplitCast consumer vs upstream product ownership | [SplitCast](splitcast-consumer.md) |
| QEMU guest configuration | [QEMU guest](qemu-guest.md) |
| Home Manager user-data moves | [Home migration](../assets/home-layout/README.md) |
| osu! display and timing research | [Display](../scripts/osu-performance/README-display.md) · [Experiments](../scripts/osu-performance/README-lab.md) |

## What's unfinished / what changed?

- [Roadmap](../ROADMAP.md) — unverified acceptance work. Do not confuse it with enabled features.
- [Knowledge update log](log.md) — dated documentation corrections, not evidence of a successful host switch.
- [Agent retrieval index](../MEMORY.md) — small, stable constraints and directions.

**Truth ordering:** check the current `flake.nix`, host feature selection and corresponding native option definitions. Tests establish only what they test. A live claim requires host + generation + timestamp + direct observation. Record failed attempts and historical operator evidence without promoting either into timeless current state.
