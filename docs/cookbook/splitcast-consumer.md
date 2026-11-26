---
type: Reference
title: "splitcast-consumer.md"
description: "Pinned SplitCast input and consumer roles"
status: stable
source_revision: 5b1c6f8b62534bbfa9a99c1d2075aad0b1db7756
sources:
  - id: source-1
    resource: https://github.com/tenzyu/nixfiles/blob/5b1c6f8b62534bbfa9a99c1d2075aad0b1db7756/flake.nix
    title: "flake.nix"
  - id: source-2
    resource: https://github.com/tenzyu/nixfiles/blob/5b1c6f8b62534bbfa9a99c1d2075aad0b1db7756/modules/50-features/media/splitcast-capture.nix
    title: "modules/50-features/media/splitcast-capture.nix"
  - id: source-3
    resource: https://github.com/tenzyu/nixfiles/blob/5b1c6f8b62534bbfa9a99c1d2075aad0b1db7756/modules/50-features/media/splitcast-production.nix
    title: "modules/50-features/media/splitcast-production.nix"
  - id: source-4
    resource: https://github.com/tenzyu/nixfiles/blob/5b1c6f8b62534bbfa9a99c1d2075aad0b1db7756/modules/50-features/media/_internal/cache.nix
    title: "modules/50-features/media/_internal/cache.nix"
---

# Consume the independent SplitCast flake

The cache URL and public signing key are enabled only when a host selects
`splitcast-production` or `splitcast-capture`. The common Nix module no
longer grants SplitCast's signing key to hosts with no SplitCast consumer.
Matching cache tags and revisions does not prove validity. Inspect actual store
paths and use the CI workflow_dispatch `cache_strict` signed-copy audit
before asserting cache completeness. A cache audit does not assert runtime
deployment.

SplitCast source is not vendored here. The `splitcast` input provides packages, NixOS prerequisites and the Home Manager agent module. The local features consume those modules without duplicating product behavior. Capture uses the existing embedded Home Manager role; neko7 production evaluates the upstream Home Manager module in its independent runtime artifact, including its peer setting. See [existing workload migration](compute-workload-migration.md).

The current `flake.lock` pins the SplitCast input at `3b2a051efc1c5f8c483d8f7f453d49f6216c7f2d`, **not** the release revision `d2205d06b0dc695c3d9b7372fafa7facee769fa9` used by the configured binary cache. The latter is an older candidate, not verified for both current Rust/Web outputs. Keep SplitCast's own Nixpkgs lock: adding a `follows` override changes derivation inputs and can invalidate store-path compatibility.

`modules/50-features/media/_internal/cache.nix` configures that release URL and the public key from `nix/cache-public-key` at the release revision. Nix still requires signatures on substitution; the diagnostic metadata audit does not establish that the locked outputs can actually be substituted. The release is `nix-cache-d2205d06b0dc695c3d9b7372fafa7facee769fa9-43561723796-1`. Its manifest SHA-256 is `fbc58a9d412b7a7c4e59f37c21835fc5cf464e677603f534bf355db43c688387`.

To select a later cached candidate, review the intended SplitCast source revision and update `flake.lock` with `nix flake update splitcast`, then update the explicit cache URL only after verifying release provenance, signatures and actual output-store paths. Do not change the pinned source merely to make a cache tag match. A lock update does not deploy SplitCast.

The capture role remains disabled. The neko7 production artifact is generated with `services.splitcast.rustCandidate = false` and its upstream user unit has no autostart target. The embedded Home Manager production role is disabled so it cannot own the same unit. No operating-system switch or service start is part of this extraction.

Run SplitCast's own verification from its repository. This consumer reuses SplitCast's package and configuration checks instead of maintaining a second implementation or test suite. The independent repository's `docs/operations.md`, `docs/design-review.md`, `docs/verification.md`, and `MEMORY.md` are the current references. The historical graphics research and isolated experiments were transferred there as non-current evidence.

Before any later deployment, evaluate the actual consumer configuration, inspect the selected package and generated TOML, confirm cgroup teardown and credential ownership, and obtain separate authorization for physical capture, privileges, firewall changes, public publication and activation. Restoring a Git input does not itself restore a running generation.

## Wiki context

Source declares the input pin and role selections. Verify the running binary, cache availability, live streaming and PoC acceptance separately. See [host state](../memory/host-state.md).
