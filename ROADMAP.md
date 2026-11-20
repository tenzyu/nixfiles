# Roadmap

This document tracks **unverified work**, not features already deployed. Host activation, service changes, destructive cleanup and publication require separate authorization.

| Priority | Work | Current implementation evidence | Acceptance criteria / failure boundary |
| --- | --- | --- | --- |
| P0 | XDG home migration | `neko5` selects `home-layout` and has an unresolved migration TODO. [#65](https://github.com/tenzyu/nixfiles/pull/65) proposes per-group holding, write admission and journal-based recovery. The prior review failed [whole-group retirement recovery](docs/adr/0002-invariant-safety.md#home-migration). Tests and final independent review for the authored repair are pending. | **Host NOT RUN.** Verify the incumbent route, ordinary app read/save/relaunch, protected writes, migration and recovery. Real apply, activation and retirement require separate approval. |
| P1 | Parsec workaround acceptance | [#64](https://github.com/tenzyu/nixfiles/pull/64) proposes missing-file initialization and read-only saved-settings and mapping review. | **NOT RUN:** verify negotiated decoder, overlay/VSync settings, touchpad false controller behavior and unaffected controllers on neko5. |
| P0 | Minecraft backup and admission recovery | [#63](https://github.com/tenzyu/nixfiles/pull/63) proposes read-only diagnosis and a guarded recovery path. Packaged restore and inert-manager fault fixtures exercise repository behavior. | **NOT RUN:** separately authorize native lock, clean stop, archive validation + restore, failed post-stop backup, manager-loss diagnosis and explicit recovery on an approved host. |
| P0 | Nix store cleaner safety | [#68](https://github.com/tenzyu/nixfiles/pull/68) makes result-link review read-only and noninteractive. | **Host NOT RUN.** Verify staged boot, mismatched current/booted/profile generations, native GC and rollback while preserving boot entries and GC roots. |
| P2 | Documentation and retrieval quality | Candidate wiki contains a source correction and duplicate consolidation. Deterministic route checks are available. | The first pair was an invalid pilot. A budget-bounded rerun and independent truth review are pending. Record observed benefit and missed criteria in the evaluation receipt. |
| P1 | OpenCode user service migration | `opencode-neko7-service.nix` exists but is not enabled in neko7 host | Confirm running version, backup DB/WAL, prove single writer and restore path, obtain switch approval |
| P1 | SplitCast consumer acceptance | Separate pinned flake; capture disabled on neko5, production feature enabled on neko7 | Verify cached derivations, consumer config, service activation state and independently tested output; separately authorize capture or publication |
| P1 | Catppuccin build-cache diagnosis | Catppuccin input and substituter configured in `flake.nix` / `nix.nix` | Compare derivation hashes, lock resolution and substitute queries before changing `follows` or pinning |
| P2 | osu! latency studies | [#69](https://github.com/tenzyu/nixfiles/pull/69) updates telemetry provenance and preserves legacy session reads. | **Host NOT RUN.** Compare matched windows with the fixed native Direct Scanout baseline. Physical latency requires independent measurement. |
| P2 | Framework/editor regression tests | Private framework, separate tools CLI, Nix tests and metadata/link checks | Test real nixd completion and evaluated host-option provenance; static docs validation cannot prove those editor behaviors |
| P2 | Host declaration ergonomics | Hosts declare concrete features using the typed seed and native Home Manager options for scoped settings | Verify live nixd/Zed completion for the host, user and embedded Home Manager option paths |

## Completion discipline

Move an item out of this roadmap only with a concrete commit, test evidence, affected host/generation and successful acceptance criteria. Source-only checks are not real hardware/runtime checks. Rollbacks of NixOS generations do not reverse Home Manager data migrations. Document ongoing decisions in [docs/memory/decisions.md](docs/memory/decisions.md) and knowledge changes in [docs/memory/log.md](docs/memory/log.md).
