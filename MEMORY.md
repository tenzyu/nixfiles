# nixfiles — agent retrieval

**Route, don't preload.** Source code is authoritative for declarations, tests for their tested contracts, and dated host receipts for runtime claims. An old note or PR cannot prove current activation.

| Task | First read | Then verify |
| --- | --- | --- |
| Host or user feature | [Host contracts](docs/memory/host-state.md) | `modules/00-hosts/<host>/configuration.nix` → selected `modules/50-features/` |
| Projection, composition or option conflict | [Architecture](docs/memory/architecture.md) · [Composition](docs/memory/composition.md) | `modules/_internal/configurations/` and `lib/`, evaluated native options |
| Dynamic execution, VM lab or preview | [Compute platform](docs/cookbook/compute-host.md) | Native Incus API, project restrictions and machine tests; no application-specific host configuration |
| State, secrets, data migration, rollback | [Decisions](docs/memory/decisions.md) · [Evidence classes](docs/memory/evidence.md) | [Cookbook](docs/cookbook/index.md), exact host/generation/time receipt |
| Prior failure, hypothesis or repeated task | [Memory index](docs/memory/index.md) · [Dreaming](docs/memory/dreaming.md) | Pinned commit/test/job and surviving counterexample |
| Unfinished work | [ROADMAP](ROADMAP.md) | Current head, acceptance gates and approval owner |

**Fixed boundaries:** Keep `configurations.nixos.<host>.module`, `local.features.<name>.enable` and `local.users.<name>.features.<name>.enable`; prefer native Nix semantics. Preserve Direct Scanout success on neko5; SplitCast product implementation is upstream. Don't infer secrets, deployment, performance or authorization from Git. Use ordinary commands inside an active direnv shell. Never activate hosts, migrate live state, rotate credentials, expose services or merge without explicit approval.

After a material decision or falsified assumption, reconcile only the affected memory concept against primary evidence; retain historical failures. [Memory update contract](docs/memory/dreaming.md).
