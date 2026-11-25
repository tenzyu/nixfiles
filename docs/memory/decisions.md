---
type: Decision Record
title: "Safety, ownership and acceptance"
description: "Durable configuration constraints and explicit operational gates"
status: stable
sources:
  - id: home
    resource: https://github.com/tenzyu/nixfiles/blob/3cea74d0db3dc6409045470f8be76688146216de/modules/50-features/home/home-migration.nix
    title: "Reviewed Home holding and cutover declaration"
  - id: game
    resource: https://github.com/tenzyu/nixfiles/blob/2137ae82047d11c5f81b22f39b846e74dc3b191f/modules/50-features/game-servers/_internal/minecraft-backup/operator.sh
    title: "Minecraft admission and backup"
  - id: parsec
    resource: https://github.com/tenzyu/nixfiles/blob/ca9e7ea1af584d27979de583b69e9425310172db/modules/50-features/services/parsec.nix
    title: "Parsec seeding and review"
  - id: osu
    resource: https://github.com/tenzyu/nixfiles/blob/8fdb01054bcb9854a8da82dad2399cb880d4b1e0/scripts/osu-performance/osu-lab.py
    title: "osu! measurement"
  - id: secret
    resource: https://github.com/tenzyu/nixfiles/blob/9638f84d5b5e8f2de1de4af401f0bbb1cd35d707/modules/50-features/security/sops-nix.nix
    title: "SOPS provider"
---

# Decisions and acceptance

## D0 — HOME maintenance direction (2026-11-23)

[ADR-0003](../adr/0003-home-layout-reuse-first.md) accepts **"HOME should require no daily attention"** as the future maintenance goal. Do not pursue physical-HOME-wide immutability, mandatory removal of every legacy dotpath, a global path-authority mechanism or automatic migration merely for tidy directory names. Prefer NixOS, Home Manager, XDG and app-native options; inspect drift on demand and retain explicit, recoverable one-off changes only when needed.

**This is not an implementation rollback of D2.** The existing #65/#70 `home-migration` pre-switch admission, retained incumbent, journaling and recovery contracts still govern any use of that code on `main`. Retirement must be tested and authorized separately. [#78](https://github.com/tenzyu/nixfiles/pull/78) and [#79](https://github.com/tenzyu/nixfiles/pull/79) are archived investigations, **not** production behavior or a pending enforcement plan.

## D1 — Code wins over stale documentation

Nix module implementation and exact host configuration supersede old README assertions. However, source inspection, Nix evaluation, build, activation, boot, and runtime behavior are different evidence tiers. A registered module does not mean the host enabled it; an enabled service is not proof of current runtime.

## D2 — Data and rollback safety

Use the ordinary app entry point to verify the incumbent route before changing it. The accepted Home policy holds the verified legacy route by group until data and references are ready for cutover. In the landed #65 implementation, Home Manager checks protected writes before its write boundary and NixOS checks the realized generation before switching. The intended holding behavior is to permit unrelated safe changes while the group stays on the legacy route. The prior VM verified incumbent-route protection and whole-group retirement recovery. The replacement also preflights the whole group when resuming ordinary apply or rollback. Switch admission leaves route-free account creation to NixOS and checks affected incumbent accounts before removing a route or account. Refuse while affected data remains or an affected HOME is unavailable. The 2026-11-20 R4 inspection failed group-resume capacity at `2ecf45d`. The capacity repair checks aggregate bytes by destination mount for copies needing a stage before any action advances, with a second check before staging each copy. R4's 2026-11-20 scoped capacity recheck passed at Home `e5b62b4` on `25a70b3`, using source inspection and the maintained direct and native VM fixture results. Treat app route, activation writes and data transfer as separate checks. Actual neko5 app and data acceptance is **NOT RUN**. [Landed Home source and evidence](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/adr/0002-invariant-safety.md#home-migration) · [Home runbook](../../assets/home-layout/README.md).

The #70 follow-up uses one path projection for planning and replay, one v2 publication classifier for fresh execution and recovery, and one per-consumer coverage rule for recovery and route admission. It keeps known journal locations discoverable across candidate generations and checks native cleanup for removal of protected ancestors. The 2026-11-20 receipts for `a14f912` include 84 direct tests, 71 packaged passes with 13 skips, and 18 guest tests plus native activation checks. Physical app acceptance, power-loss persistence and discovery of unrecorded pre-locator state still require separate evidence. [Follow-up and receipts](https://github.com/tenzyu/nixfiles/pull/70) · [Tested source](https://github.com/tenzyu/nixfiles/commit/a14f912f82feae8f5fadc333443209b9783eb013).

The one-rename fixture on `79cdd9e` preserved the migrated Zsh history and v2 journal together under a different name. The locator reported the journal directory missing, and the gate admitted the unchanged intended route as fresh. The correction checks journal availability before classifying a route as fresh. With unknown history it admits an unchanged installed held route only when every selected and fixed path has user data and the write checks pass. The fresh control uses successful journal discovery. [Regression fixture](https://github.com/tenzyu/nixfiles/commit/21bb42e7c3d0e167ad7bbda283abafc3d3066d0f) · [Correction](https://github.com/tenzyu/nixfiles/commit/28241b1516d5e3a593d75ac35d35c60d92db3428).

When both roots contain user data, preserve both and hold the group while authority is unresolved. Apparent equality conveys no authority to mutate either copy. Apply requires a separate approved offline window. Retiring a named copy requires its own authorization and a reversible recovery path. Existing links and references need operator review. After interruption, reconcile the journal with the actual entries and preserve ambiguous copies. A generation rollback does not undo a data move.

Nix owns store liveness and GC. Inspect the native roots and system generation links; no custom cleanup command or routine generation pruning. Explicit approval remains necessary for destructive maintenance. [Store maintenance](../cookbook/nix-store-clean.md).

## D3 — One persistent service writer

The OpenCode Home Manager service is a *candidate*, not active host configuration. Never start it concurrently with a manually managed server using the same database, even on separate ports. Migration requires compatible version, offline data backup and approved switch. See [migration playbook](../cookbook/opencode-neko7-migration.md).

## D4 — Repository ownership boundaries

SplitCast source, package tests and PoC acceptance belong to its independent repository; nixfiles only pins and integrates its flake. Pinning a cache or enabling a role does not prove a particular binary is now running. See [consumer](../cookbook/splitcast-consumer.md).

## D5 — Measurement scope

Protect the current native Jay Direct Scanout and scoped audio policy. Prior Hyprland and osu-lab measurements are [historical](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/scripts/osu-performance/README-lab.md); compositor counters do not measure event-to-photon or audio-onset latency. Require matched physical observations to claim an improvement.

## D6 — Native semantics over a private configuration language

The host remains an explicit list of `local.features` and `local.users.*.features`. The adapter exists to preserve typed editor completion and project host selections into native NixOS/Home Manager modules. Prefer Nix builtins and nixpkgs `lib` where semantics match. Named composition functions distinguish **ordered values**, **disjoint fields**, and **deliberate shallow replacement**; do not generalize them into another `mkMerge` or hide priority/provenance. [ADR-0001](../adr/0001-canonical-feature-semantics.md) specifies the canonical `null | false | true` contract: an unspecified selection produces no target definition, while an explicit boolean is resolved by native NixOS/Home Manager precedence.

## D7 — Persistent service data needs independent migration acceptance

For neko7, the individual Minecraft feature declares Minecraft data under `/srv/minecraft`, with Tailscale node identity under the persistent service HOME. The [runbook](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/cookbook/game-server-srv-migration.md) contains a 2026-11-18 record of a completed cutover, including generation 68 and a player login. It is **historical**, not proof that today's runtime is healthy. Re-running the initial copy into an existing target is prohibited; backing up and rolling back NixOS does not reverse game-world writes.

## D8 — A secrets provider is not a provisioned secret

Both neko5 and neko7 select `sops-nix`. An age key, encrypted manifest, permission boundary, successful decryption and service reload are **separate** operational facts. Do not assert them from the host feature flag. Preserve `tailscaled` state across reconfiguration; avoid accidental node re-enrollment or token exposure. See [secrets](../cookbook/secrets-and-tailscale.md).

## D9 — App-owned settings and uncertain service outcomes

Parsec owns its saved settings and controller mappings. The #64 implementation seeds missing files independently and skips an incumbent without opening it. The review command inspects saved values and modes. A legacy entry suppresses JSON seeding when observed before publication. Where legacy import precedence matters, seed with Parsec stopped. A saved-value match does not establish effective client behavior. [Landed Parsec source](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/adr/0002-invariant-safety.md#parsec) · [Parsec runbook](../../assets/parsec-activation/README.md).

The #63 Minecraft operator keeps the same-boot admission guard after a manager job whose result is unconfirmed. Diagnose both managers, then clear the guard only after reconciliation while holding the original lock. A failed post-stop backup never requests an automatic restart. Use the reported archive target to verify any candidate archive separately from service recovery. Keep ARK and Rust disabled on neko7 and leave updates, retention and sharing with their existing owners. [Minecraft runbook](../../modules/50-features/game-servers/_internal/minecraft-backup/README.md#diagnose-and-recover).

The local Safety Core operations follow real consumers. Keep Python for the Home mover, Shell for Minecraft publication, Parsec's anonymous stage, and the separate TypeScript process boundaries. The Rust lookup experiment has been retired to the [archive](../archive/README.md); no Rust safety port is maintained. No proposed implementation or packaged fixture substitutes for host acceptance. [Consumer and port decisions](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/adr/0002-invariant-safety.md#q8--safety-core-and-rust).

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
