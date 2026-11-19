# ADR-0001 — Canonical feature selection semantics

- **Status at proposal:** Accepted (semantics); implementation proposed in [PR #47](https://github.com/tenzyu/nixfiles/pull/47); verification pending
- **Date:** 2026-11-19
- **Pre-change source:** [Embedded Home Manager materializer before PR #47](https://github.com/tenzyu/nixfiles/blob/e3cece3ed2717448bdd3f2307479fe58df62bd32/modules/_internal/configurations/materializers/home-manager.nix)
- **Landed source:** [PR #47 squash commit](https://github.com/tenzyu/nixfiles/commit/0daacae75f19dc2b01712c26471b42b2c6bc9ca3)
- **Scope:** `configurations.nixos.*.module.local.features`, `local.users.*.features`, standalone and embedded Home Manager

## Context

The editor-facing, typed `configurations.*` host seed selects registered NixOS / Home Manager features. A seed option is `types.nullOr types.bool` with default `null`. The corresponding target `local.features.*.enable` is a Native `mkEnableOption` with default `false`. NixOS and Home Manager have separate module evaluators.

Before this change, `enabledFeatures` forwarded only effective `true` from the evaluated NixOS user options to embedded Home Manager. This discarded an explicit host `false`: e.g. the `adapter-home-default` fixture selected `false` but HM's `mkDefault true` still won. After NixOS user evaluation, an implicit `false` and a host-selected `false` are indistinguishable without separately retaining the host seed.

## Decision

**Selection values are `null | false | true`, not an implicit boolean.** At a target NixOS/HM module boundary:

| Host selection | Target host definition | Other target definition | Effective result |
| --- | --- | --- | --- |
| `null` | absent | absent | `false` (`mkEnableOption` default) |
| `null` | absent | `mkDefault true` | `true` |
| `null` | absent | `mkDefault false` | `false` |
| `false` | regular `false` | `mkDefault true` | `false` |
| `true` | regular `true` | `mkDefault false` | `true` |
| `false` | regular `false` | regular `true` | Native conflict |
| `true` | regular `true` | regular `false` | Native conflict |
| `false` | regular `false` | `mkForce true` | `true` |
| `true` | regular `true` | `mkForce false` | `false` |

Seed-side `mkDefault` / `mkForce` wrappers are resolved by flake-parts **before** target projection. Their priority is not transported. Native target priorities and conflict behavior remain authoritative.

For embedded Home Manager, retain the typed host user selection `selected` separately from the evaluated NixOS `local.users.<user>.features` boolean `effective`. For each feature:

```text
emit_definition := selected != null OR effective == true
emitted_value   := effective
```

This keeps positive user-option contributions, honors native NixOS user `mkForce` results, preserves explicit host `false`, and never turns an unselected native `false` into an HM definition. HM receives a regular-priority definition, so HM `mkForce` still wins and equal-priority disagreement still errors. The host authoring API, target option types, disabled-user filtering, and user→system soft projection/assertion remain unchanged.

## Feature dependencies and provenance

`steam -> gaming-core` is an **optional soft default** in current source: `steam` adds `gaming-core.enable = lib.mkDefault true` in both module systems. This does **not** prove a mandatory runtime dependency. If evidence establishes a hard requirement, validate it with a feature-local assertion rather than a new runtime registry or hard-coded host list.

`definitionsWithLocations` reports only winning definitions after native priority filtering, with `mkOverride` wrappers removed. `highestPrio` exposes the surviving priority group, not individual lost definitions or a complete dependency graph. Source scans are best-effort location hints, not evaluation evidence. Trace reports `winning_priority` for accessible NixOS option paths; nested Home Manager priority remains unresolved and is represented as `null`, not guessed.

## Alternatives rejected

- Forwarding every evaluated NixOS user `false` to HM: suppresses HM defaults for unselected features.
- Converting host `null` to `false`: destroys the distinction between no definition and explicit disable.
- Dropping explicit `false`: reproduces the bug.
- Hard-coding all dependencies into each host, prohibiting `mkDefault true`, adding `mkForce` to win conflicts, inventing a private priority/dependency evaluator or changing the host authoring API: unnecessary and inconsistent with Native Nix semantics.

## Consequences / regression boundaries

Explicit host opt-outs now defeat soft HM defaults. Unselected HM features can still activate through their own native defaults. NixOS user-feature overrides remain observable in HM at their evaluated value, but not at their original NixOS priority. The existing `adapter-home-default` fixture must change `embeddedDefault = true` to `false`; changing the expectation without evaluating the actual embedded HM would be insufficient.

Regression requirements: null / both booleans, equal-priority conflicts, `mkDefault` / `mkForce`, disabled users, NixOS/HM separate scopes, system/user same-name projection, standalone HM, package-policy isolation, Steam soft dependency, and feature trace provenance. Verify `nix run -L .#framework-test` and compare evaluated feature / packages / service settings across neko5, neko6 and neko7 before merge. No activation or Home Manager switch is authorized by this ADR.

## Unresolved / acceptance gates

1. Check additional NixOS user-option definition sources and edge-case priority behavior against the pinned Nixpkgs/HM evaluator with actual Nix tests.
2. Exact nested HM option provenance is unavailable through a stable path; retain `null` until a verified non-fragile interface exists.
3. CI and before/after host impact comparison must pass; source review alone cannot certify an unchanged package/service closure.

**Rollback:** revert the proposed adapter, trace, test and documentation changes. If a host has separately been activated, restoring its generation requires separate operator approval; a Git revert does not roll back persistent data.
