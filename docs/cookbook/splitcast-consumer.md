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

The configuration enables the cache URL and public signing key only when a host selects
`splitcast-production` or `splitcast-capture`. The common Nix module no
longer grants SplitCast's signing key to hosts with no SplitCast consumer.
Matching cache tags and revisions does not prove validity. Inspect actual store
paths and use the CI workflow_dispatch `cache_strict` signed-copy audit
before asserting cache completeness. A cache audit does not assert runtime
deployment.

nixfiles does not vendor SplitCast source. The `splitcast` input provides packages, NixOS prerequisites and the Home Manager agent module. The local features consume those modules without duplicating product behavior. Capture uses the existing embedded Home Manager role; neko7 production evaluates the upstream Home Manager module in its independent runtime artifact, including its peer setting. See [existing workload migration](compute-workload-migration.md).

The current `flake.lock` pins SplitCast at `b6fcf1588fec4c42b0e22df58f3bca53c2f51b6f`, matching the verified release source. Keep SplitCast's own Nixpkgs lock. A `follows` override changes derivation inputs and can invalidate store-path compatibility.

`modules/50-features/media/_internal/cache.nix` configures that release URL and the public key from `nix/cache-public-key` at the release revision. Nix still requires signatures during substitution. The metadata audit does not establish that the cache can supply the locked outputs. The release is [`nix-cache-b6fcf1588fec4c42b0e22df58f3bca53c2f51b6f-45916419238-1`](https://github.com/tenzyu/splitcast/releases/tag/nix-cache-b6fcf1588fec4c42b0e22df58f3bca53c2f51b6f-45916419238-1). Its manifest SHA-256 is `81810201f03163678fb90c871972fb316942ff592601d3f297bcd690426f7281`. The independent [publisher consumer](https://github.com/tenzyu/splitcast/actions/runs/45916419238/job/140244053571) fetched the native closure with builds disabled. The strict consumer audit verifies both the SplitCast signing key and the official NixOS cache key in an isolated store; it does not activate a service.

To select a later cached candidate, review the intended SplitCast source revision. Run `nix flake update splitcast` to update `flake.lock`. Verify release provenance, signatures, and output store paths before updating the cache URL. Do not change the pinned source merely to make a cache tag match. A lock update does not deploy SplitCast.

The capture role remains disabled. The neko7 production artifact is generated with `services.splitcast.rustCandidate = false` and its upstream user unit has no autostart target. The embedded Home Manager production role is disabled so it cannot own the same unit. No operating-system switch or service start is part of this extraction.

Run SplitCast's own verification from its repository. This consumer reuses SplitCast's package and configuration checks instead of maintaining a second implementation or test suite. The independent repository's `docs/operations.md`, `docs/design-review.md`, `docs/verification.md`, and `MEMORY.md` are the current references. The historical graphics research and isolated experiments were transferred there as non-current evidence.

Before any later deployment, evaluate the actual consumer configuration, inspect the selected package and generated TOML, confirm cgroup teardown and credential ownership, and obtain separate authorization for physical capture, privileges, firewall changes, public publication and activation. Restoring a Git input does not itself restore a running generation.

## Wiki context

Source declares the input pin and role selections. Verify the running binary, cache availability, live streaming and PoC acceptance separately. See [host state](../memory/host-state.md).
