# Roadmap

This document tracks **unverified work**, not features already deployed. Host activation, service changes, destructive cleanup and publication require separate authorization.

| Priority | Work | Current implementation evidence | Acceptance criteria / failure boundary |
| --- | --- | --- | --- |
| P0 | XDG home migration | `neko5` has `home-layout.enable = true` and an unresolved migration TODO; activation is always fail-closed on pending moves; migration requires a separate `home-layout-migrate apply` invocation | Verify conflict handling, backups, interruption recovery and real home state; require separate approval for a manual apply; abort on unresolved profile/credential conflicts |
| P0 | Nix store cleaner safety | `assets/nix-store-clean/cli.py` uses native GC and guarded pruning | VM test staged boot, mismatched current/booted/profile generations, GC and rollback; preserve boot entries and GC roots |
| P2 | Documentation and retrieval quality | Deterministic OKF/link/source checks, Git dependency drift detection and a retrieval-route smoke fixture are implemented; no blind agent comparison has been run | Maintain coverage and run paired Search-only vs Wiki+Search source-bound questions before claiming answer-quality or token savings |
| P1 | OpenCode user service migration | `opencode-neko7-service.nix` exists but is not enabled in neko7 host | Confirm running version, backup DB/WAL, prove single writer and restore path, obtain switch approval |
| P1 | SplitCast consumer acceptance | Separate pinned flake; capture disabled on neko5, production feature enabled on neko7 | Verify cached derivations, consumer config, service activation state and independently tested output; separately authorize capture or publication |
| P1 | Catppuccin build-cache diagnosis | Catppuccin input and substituter configured in `flake.nix` / `nix.nix` | Compare derivation hashes, lock resolution and substitute queries before changing `follows` or pinning |
| P2 | osu! latency studies | `neko5-osu-first`, `osu-lab`, `osu-display` provide candidate controls and telemetry | Controlled A/B, tail latency and error reporting with fixed DSO baseline; never infer input-to-photon from indirect telemetry |
| P2 | Framework/editor regression tests | Private framework, separate tools CLI, Nix tests and metadata/link checks | Test real nixd completion and evaluated host-option provenance; static docs validation cannot prove those editor behaviors |
| P2 | Host declaration ergonomics | Hosts declare concrete features using the typed seed and native Home Manager options for scoped settings | Verify live nixd/Zed completion for the host, user and embedded Home Manager option paths |

## Completion discipline

Move an item out of this roadmap only with a concrete commit, test evidence, affected host/generation and successful acceptance criteria. Source-only checks are not real hardware/runtime checks. Rollbacks of NixOS generations do not reverse Home Manager data migrations. Document ongoing decisions in [docs/memory/decisions.md](docs/memory/decisions.md) and knowledge changes in [docs/memory/log.md](docs/memory/log.md).
