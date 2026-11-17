---
type: Decision Record
title: "Safety and evidence"
description: "Evidence tiers and conservative operational decisions"
status: stable
source_revision: 22191670806242933bc156e4a5e0cd9ad3ea14f1
sources:
  - id: src-1
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/50-features/nix-store-clean.nix
    title: "modules/50-features/nix-store-clean.nix"
  - id: src-2
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/50-features/home-migration.nix
    title: "modules/50-features/home-migration.nix"
  - id: src-3
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/50-features/opencode-neko7-service.nix
    title: "modules/50-features/opencode-neko7-service.nix"
  - id: src-4
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/50-features/splitcast-production.nix
    title: "modules/50-features/splitcast-production.nix"
  - id: src-5
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/50-features/neko5-osu-first.nix
    title: "modules/50-features/neko5-osu-first.nix"
---

# Decisions and acceptance

## D1 — Code wins over stale documentation

Nix module implementation and exact host configuration supersede old README assertions. However, source inspection, Nix evaluation, build, activation, boot, and runtime behavior are different evidence tiers. A registered module does not mean the host enabled it; an enabled service is not proof of current runtime.

## D2 — Data and rollback safety

The XDG migration includes data movement, collision checks and journals. NixOS generation rollback **does not reverse renames of user data**. `neko5` contains an unresolved migration TODO. See [home migration runbook](../assets/home-layout/README.md).

The Nix store cleaner does not ignore GC roots; `prune-system` needs explicit confirmation and full staged-boot/rollback VM acceptance. Reclaiming a large amount of space is not evidence of safe deletion. See [Nix store cleanup](nix-store-clean.md).

## D3 — One persistent service writer

The OpenCode Home Manager service is a *candidate*, not active host configuration. Never start it concurrently with a manually managed server using the same database, even on separate ports. Migration requires compatible version, offline data backup and approved switch. See [migration playbook](opencode-neko7-migration.md).

## D4 — Repository ownership boundaries

SplitCast source, package tests and PoC acceptance belong to its independent repository; nixfiles only pins and integrates its flake. Pinning a cache or enabling a role does not prove a particular binary is now running. See [consumer](splitcast-consumer.md).

## D5 — Measurement scope

`osu-lab` samples OS and compositor telemetry. It cannot by itself establish event-to-photon or physical audio-onset latency. Any optimization remains a hypothesis until controlled A/B and independently verified output. See [latency lab](../scripts/osu-performance/README-lab.md).

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
