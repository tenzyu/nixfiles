---
okf_version: "0.2"
---

# nixfiles — LLM Wiki

This OKF v0.2 bundle is a **compiled, source-grounded understanding** of the repository, not a duplicate of its Nix modules.

## Concepts

- [Architecture](architecture.md) — feature registry, seed compaction, materializers and Home Manager projection
- [Host state](host-state.md) — configuration declarations, disabled features and runtime uncertainty
- [Decisions](decisions.md) — safety, ownership boundaries and validation gates
- [Knowledge maintenance](schema.md) — provenance, evidence labels, Dreaming reconciliation

## Runbooks and references

- [Nix store cleanup](nix-store-clean.md)
- [OpenCode devShell / direnv integration](opencode-devshells.md)
- [OpenCode service migration](opencode-neko7-migration.md)
- [SplitCast consumer](splitcast-consumer.md)
- [XDG home migration](../assets/home-layout/README.md)
- [osu! display experiments](../scripts/osu-performance/README-display.md)
- [osu! latency lab](../scripts/osu-performance/README-lab.md)

## Separate planning and history

- [Roadmap](../ROADMAP.md) — proposed and unverified work
- [Update log](log.md) — Wiki edit history

## Truth ordering

Exact implementation and its conditions establish what is declared; reproducible tests establish what was tested; host + generation + time establish what actually ran. Previous documentation and conversation claims are context rather than stronger evidence. **Implementation wins over contradictory prose, but code cannot establish current runtime state.**
