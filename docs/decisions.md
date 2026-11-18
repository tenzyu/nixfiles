---
type: Decision Record
title: "Safety, ownership and acceptance"
description: "Durable configuration constraints and explicit operational gates"
status: stable
source_revision: 438aa02b426db0a5962dd0102f0cbb04a5191c06
sources:
  - id: gc
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/50-features/nix/nix-store-clean.nix
    title: "Nix store cleaner"
  - id: home
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/50-features/home/home-migration.nix
    title: "Home migration"
  - id: game
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/50-features/game-servers/minecraft.nix
    title: "Minecraft"
  - id: secret
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/modules/50-features/security/sops-nix.nix
    title: "SOPS provider"
---

# Decisions and acceptance

## D1 — Code wins over stale documentation

Nix module implementation and exact host configuration supersede old README assertions. However, source inspection, Nix evaluation, build, activation, boot, and runtime behavior are different evidence tiers. A registered module does not mean the host enabled it; an enabled service is not proof of current runtime.

## D2 — Data and rollback safety

The XDG migration includes data movement, collision checks and journals. Home Manager activation is strictly check-only; data moves require a separate, explicitly approved `home-layout-migrate apply`. NixOS generation rollback **does not reverse renames of user data**. `neko5` contains an unresolved migration TODO. See [home migration runbook](../assets/home-layout/README.md).

The Nix store cleaner does not ignore GC roots; `prune-system` needs explicit confirmation and full staged-boot/rollback VM acceptance. Reclaiming a large amount of space is not evidence of safe deletion. See [Nix store cleanup](nix-store-clean.md).

## D3 — One persistent service writer

The OpenCode Home Manager service is a *candidate*, not active host configuration. Never start it concurrently with a manually managed server using the same database, even on separate ports. Migration requires compatible version, offline data backup and approved switch. See [migration playbook](opencode-neko7-migration.md).

## D4 — Repository ownership boundaries

SplitCast source, package tests and PoC acceptance belong to its independent repository; nixfiles only pins and integrates its flake. Pinning a cache or enabling a role does not prove a particular binary is now running. See [consumer](splitcast-consumer.md).

## D5 — Measurement scope

`osu-lab` samples OS and compositor telemetry. It cannot by itself establish event-to-photon or physical audio-onset latency. Any optimization remains a hypothesis until controlled A/B and independently verified output. See [latency lab](../scripts/osu-performance/README-lab.md).

## D6 — Native semantics over a private configuration language

The host remains an explicit list of `local.features` and `local.users.*.features`. The adapter exists to preserve typed editor completion and project host selections into native NixOS/Home Manager modules. Prefer Nix builtins and nixpkgs `lib` where semantics match. Named composition functions distinguish **ordered values**, **disjoint fields**, and **deliberate shallow replacement**; do not generalize them into another `mkMerge` or hide priority/provenance.

## D7 — Persistent service data needs independent migration acceptance

For neko7, `game-srv.enable = true` declares Minecraft data under `/srv/minecraft`, with Tailscale node identity under the persistent service HOME. The [runbook](game-server-srv-migration.md) contains a 2026-11-18 record of a completed cutover, including generation 68 and a player login. It is **historical**, not proof that today's runtime is healthy. Re-running the initial copy into an existing target is prohibited; backing up and rolling back NixOS does not reverse game-world writes.

## D8 — A secrets provider is not a provisioned secret

Both neko5 and neko7 select `sops-nix`. An age key, encrypted manifest, permission boundary, successful decryption and service reload are **separate** operational facts. Do not assert them from the host feature flag. Preserve `tailscaled` state across reconfiguration; avoid accidental node re-enrollment or token exposure. See [secrets](secrets-and-tailscale.md).

## Evidence requirements

| Claim | Required evidence |
| --- | --- |
| Declared | Exact source revision, option and condition |
| Evaluates | Target and successful evaluation exit |
| Builds | Reproducible derivation and output |
| Functional | Fixture/VM scenarios with expected and observed results |
| Running | Host, generation, process/unit and timestamp |
| Accepted | Functional outcome, regression checks and rollback validation |

Unfinished checks belong in [ROADMAP](../ROADMAP.md). Knowledge curation rules belong in [schema](schema.md).
