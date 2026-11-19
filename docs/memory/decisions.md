---
type: Decision Record
title: "Safety, ownership and acceptance"
description: "Durable configuration constraints and explicit operational gates"
status: stable
source_revision: 9638f84d5b5e8f2de1de4af401f0bbb1cd35d707
sources:
  - id: gc
    resource: https://github.com/tenzyu/nixfiles/blob/9638f84d5b5e8f2de1de4af401f0bbb1cd35d707/modules/50-features/nix/nix-store-clean.nix
    title: "Nix store cleaner"
  - id: home
    resource: https://github.com/tenzyu/nixfiles/blob/9638f84d5b5e8f2de1de4af401f0bbb1cd35d707/modules/50-features/home/home-migration.nix
    title: "Home migration"
  - id: game
    resource: https://github.com/tenzyu/nixfiles/blob/9638f84d5b5e8f2de1de4af401f0bbb1cd35d707/modules/50-features/game-servers/minecraft.nix
    title: "Minecraft"
  - id: secret
    resource: https://github.com/tenzyu/nixfiles/blob/9638f84d5b5e8f2de1de4af401f0bbb1cd35d707/modules/50-features/security/sops-nix.nix
    title: "SOPS provider"
---

# Decisions and acceptance

## D1 — Code wins over stale documentation

Nix module implementation and exact host configuration supersede old README assertions. However, source inspection, Nix evaluation, build, activation, boot, and runtime behavior are different evidence tiers. A registered module does not mean the host enabled it; an enabled service is not proof of current runtime.

## D2 — Data and rollback safety

[ADR-0002](../adr/0002-invariant-safety.md#convergence-decisions) records accepted policy, source pins, and pending code dependencies. Home Manager's migration step is read-only. In [PR #65](https://github.com/tenzyu/nixfiles/pull/65), pending moves and reviewed repair proposals warn before the write boundary. Unsafe plans and native Home Manager conflicts still block. Both populated paths stay in place even when a comparison reports an apparent match. Only a separate approved apply can commit a no-replace move. Existing links and reference files still require operator review. After interruption, compare actual entries and preserved copies with the journal before deciding what to restore. Generation rollback cannot reverse a data rename. The unresolved neko5 migration TODO still needs a real-host receipt. [Home runbook](../../assets/home-layout/README.md).

The Nix store cleaner does not ignore GC roots; `prune-system` needs explicit confirmation and full staged-boot/rollback VM acceptance. Reclaiming a large amount of space is not evidence of safe deletion. See [Nix store cleanup](../cookbook/nix-store-clean.md).

## D3 — One persistent service writer

The OpenCode Home Manager service is a *candidate*, not active host configuration. Never start it concurrently with a manually managed server using the same database, even on separate ports. Migration requires compatible version, offline data backup and approved switch. See [migration playbook](../cookbook/opencode-neko7-migration.md).

## D4 — Repository ownership boundaries

SplitCast source, package tests and PoC acceptance belong to its independent repository; nixfiles only pins and integrates its flake. Pinning a cache or enabling a role does not prove a particular binary is now running. See [consumer](../cookbook/splitcast-consumer.md).

## D5 — Measurement scope

`osu-lab` samples OS and compositor telemetry. It cannot by itself establish event-to-photon or physical audio-onset latency. Any optimization remains a hypothesis until controlled A/B and independently verified output. See [latency lab](../../scripts/osu-performance/README-lab.md).

## D6 — Native semantics over a private configuration language

The host remains an explicit list of `local.features` and `local.users.*.features`. The adapter exists to preserve typed editor completion and project host selections into native NixOS/Home Manager modules. Prefer Nix builtins and nixpkgs `lib` where semantics match. Named composition functions distinguish **ordered values**, **disjoint fields**, and **deliberate shallow replacement**; do not generalize them into another `mkMerge` or hide priority/provenance. [ADR-0001](../adr/0001-canonical-feature-semantics.md) specifies the canonical `null | false | true` contract: an unspecified selection produces no target definition, while an explicit boolean is resolved by native NixOS/Home Manager precedence.

## D7 — Persistent service data needs independent migration acceptance

For neko7, `game-srv.enable = true` declares Minecraft data under `/srv/minecraft`, with Tailscale node identity under the persistent service HOME. The [runbook](../cookbook/game-server-srv-migration.md) contains a 2026-11-18 record of a completed cutover, including generation 68 and a player login. It is **historical**, not proof that today's runtime is healthy. Re-running the initial copy into an existing target is prohibited; backing up and rolling back NixOS does not reverse game-world writes.

## D8 — A secrets provider is not a provisioned secret

Both neko5 and neko7 select `sops-nix`. An age key, encrypted manifest, permission boundary, successful decryption and service reload are **separate** operational facts. Do not assert them from the host feature flag. Preserve `tailscaled` state across reconfiguration; avoid accidental node re-enrollment or token exposure. See [secrets](../cookbook/secrets-and-tailscale.md).

## D9 — App-owned settings and uncertain service outcomes

Parsec owns its saved settings and controller mappings. [PR #64](https://github.com/tenzyu/nixfiles/pull/64) keeps application-compatible first-run seeds and adds read-only comparison for the intended keys and controller ID. A saved-value match does not establish effective client behavior. Preserve the original before a manual edit, control its writers, and verify it in the app. [Parsec runbook](../../assets/parsec-activation/README.md).

Minecraft's [PR #63](https://github.com/tenzyu/nixfiles/pull/63) keeps the same-boot admission guard after a manager job whose result is unconfirmed. Diagnose both managers, then clear the guard only after reconciliation while holding the original lock. A failed post-stop backup never requests an automatic restart. An uncertain archive and service recovery require separate decisions. Keep ARK and Rust disabled on neko7 and leave updates, retention and sharing with their existing owners. [Minecraft runbook](../../modules/50-features/game-servers/_internal/minecraft-backup/README.md#diagnose-and-recover).

The local Safety Core operations follow real consumers. Keep Python for the Home mover, Shell for Minecraft publication, Parsec's anonymous stage, and the separate TypeScript process boundaries. Keep Rust as an opt-in lookup fixture outside host closures. No proposed implementation or packaged fixture substitutes for host acceptance. [Consumer and port decisions](../adr/0002-invariant-safety.md#q8--safety-core-and-rust).

## Evidence requirements

| Claim | Required evidence |
| --- | --- |
| Declared | Exact source revision, option and condition |
| Evaluates | Target and successful evaluation exit |
| Builds | Reproducible derivation and output |
| Functional | Fixture/VM scenarios with expected and observed results |
| Running | Host, generation, process/unit and timestamp |
| Accepted | Functional outcome, regression checks and rollback validation |

Unfinished checks belong in [ROADMAP](../../ROADMAP.md). Knowledge curation rules belong in [schema](dreaming.md).
