# Compute platform resource and identity design

## Resource ownership

NixOS owns machine configuration, systemd supervision, KVM/namespace access, drivers, storage mounts, Nix store/GC and firewall. Incus owns dynamically created VM/container instances, profiles, images, volumes and network state. Nix profiles own immutable release pointers for incumbent services. Rootless Docker owns OCI runtime objects; NixOS tests own disposable test topology. Each manager is authoritative only for its own live objects.

OpenTofu plans and applies declarative infrastructure changes through providers. It maintains its own state. It can own operator-managed durable Incus projects/instances or external Cloudflare/Auth0 objects if that becomes useful; do not simultaneously manage those same objects with Incus preseed or manual updates. It does not execute a VM itself. Nixus (infinisil/nixus) is an experimental multi-host NixOS deployment module system. The current flake-parts configuration does not require a second host evaluation or deployment system. Neither is a mandatory dependency.

## Future identity and transport boundaries

Use an authenticated overlay as the transport access boundary, not as application authorization. Keep the physical-uplink deny rule independent of the selected overlay; explicitly admit a new authenticated virtual interface/transport after its crypto, peer identity, key lifecycle, routing, firewall and failure tests. FEC/reliability alone does not supply a secure mesh, encryption or NAT traversal. Do not replace Tailscale with a direct UDP listener or widen the uplink rule for SplitCast without evidence and approval. The supplied Flestr source implements authenticated pairwise media transport with Noise IK and TURN-less ICE, not a routed overlay. Existing outbound UDP/conntrack semantics can support mutually initiated ICE without opening an inbound application port. See [Flestr ingress review](flestr-ingress.md) for exact source boundaries, caveats and new generic UDP test. Flestr integration belongs to SplitCast.

For future MCP/API/website auth, separate OAuth/OIDC authorization server (e.g. Auth0), resource server (MCP/app), application authorization policy and tunnel edge (e.g. Cloudflare). A valid access token must match issuer, audience/resource, expiry and scope, not merely arrive from a mesh IP. Do not commit client secrets. A public Cloudflare tunnel creates externally reachable ingress even without an open port. It requires a separately approved exception to the current Tailnet-only policy. Private WARP/Access paths also need an explicit trust decision. No public edge, identity service, tenant or credential is provisioned here.

T3 remains one existing control plane; no speculative per-agent sandbox is activated. Future worker identities should separate session state from execution credentials, offer restricted native backends, and preserve provider/tool/worktree workflows with positive and negative integration tests. The existing admin user is not a sandbox boundary.

## Repository organization

Keep the native feature selection API and numbered directories. Host placement and physical resource inventory stay in `00-hosts`; flake/evaluation/check plumbing in `10-foundations`; independent workload artifacts in `40-workloads`; reusable native features in `50-features` (hardware, networking, containers, monitoring, development). Separate immutable Nix store from mutable workload state and operator secrets; avoid inventing another module DSL. The changes are limited to the compute platform and do not reorganize unrelated hosts. The host's feature list is grouped by physical machine, ingress, execution, control plane/telemetry, workload placement and common environment without changing the typed API. CI boots the native service modules on NixOS fixture VMs and probes local readiness and external TCP denial, separately from the Incus image builds. Exact-image nested Incus lifecycle, update and isolated restore remain follow-up acceptance gates.

See the [compute platform procedures](compute-platform-operations.md).
