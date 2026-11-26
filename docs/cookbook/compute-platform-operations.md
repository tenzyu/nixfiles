# Compute platform operations

## Resource ownership

NixOS owns machine configuration, systemd supervision, KVM/namespace access, drivers, storage mounts, Nix store/GC and firewall. Incus owns dynamically created VM/container instances, profiles, images, volumes and network state. Nix profiles own immutable release pointers for incumbent services. Rootless Docker owns OCI runtime objects; NixOS tests own disposable test topology. Each manager is authoritative only for its own live objects.

OpenTofu is a provider-backed declarative infrastructure plan/apply tool with its own state. It can own operator-managed durable Incus projects/instances or external Cloudflare/Auth0 objects if that becomes useful; do not simultaneously manage those same objects with Incus preseed or manual updates. It does not execute a VM itself. Nixus (infinisil/nixus) is an experimental multi-host NixOS deployment module system. The current flake-parts configuration does not require a second host evaluation or deployment system. Neither is a mandatory dependency.

## Dashboard and observability

Use existing authenticated SSH over the Tailnet (not Funnel):

```sh
ssh -N -o ExitOnForwardFailure=yes \
  -L 13000:127.0.0.1:13000 \
  -L 9090:127.0.0.1:9090 \
  -L 8443:127.0.0.1:8443 \
  -L 18080:127.0.0.1:18080 \
  -L 3773:127.0.0.1:3773 neko7
```

Open http://localhost:13000/d/neko7-platform/ . Grafana is a provisioned read-only viewer, with no default admin creation and no public listener. Any local host user can read local telemetry; this is not an isolation boundary between agents. Prometheus uses 30s scraping, 7d retention, 2GB retention-size target (WAL/head overhead is additional). Incus metrics use a distinct local read-only HTTPS listener without client auth; the management API retains its certificate authentication. The metrics scrape accepts the local self-signed certificate; never apply that exception to a remote host. GPU data requires the actual NVIDIA driver/device. Systemd system units, endpoint probes and Incus instance labels are native inventory. User-unit details, journals, historical GPU per-process data and runtime route inventory are not unified; inspect `journalctl --user`, `journalctl -u UNIT`, `incus monitor`, and native Caddy API below. No unauthenticated telemetry listener is opened to Tailnet or LAN. Do not add a public proxy for Grafana or Prometheus.

## Generic preview gateway

For an app that requires the browser's origin root, an authorized SSH client should use `ssh -N -L 18081:GUEST_IP:APP_PORT neko7`; browser http://localhost:18081/. An SSH SOCKS forward (`ssh -N -D 127.0.0.1:1080 neko7`) is also available for an authorized client; it is not a new host listener or an agent-specific proxy.

For a short, supervised, operator-approved HTTP sharing session only, use the native Caddy API. Never publish an ephemeral agent instance to a less-trusted audience via an IP-only route; use SSH instead. Loopback permission is not an upstream allowlist. This is not an autonomous publication controller. The gateway binds only loopback TCP 18080 and is cgroup-restricted to local/Incus lab addresses. The admin socket is root/service-owned; **never grant agents unrestricted Caddy admin**, even if they can request a preview. This is a separate proxy process, not the authentication gateway for production. No route is installed at boot. Example (substitute a live lab IP and a unique name; confirm identity and app port):

```sh
sudo incus list --project lab
sudo curl -fsS --unix-socket /run/neko7-preview/admin.sock http://localhost/config/apps/http/servers/preview/routes
jq -n --arg dial '10.77.41.42:8080' '{
  "@id":"example-preview",
  match:[{path:["/p/example/*"]}],
  handle:[{handler:"rewrite",strip_path_prefix:"/p/example"},
          {handler:"reverse_proxy",upstreams:[{dial:$dial}]}]
}' | sudo curl -fsS --unix-socket /run/neko7-preview/admin.sock \
  -X PUT -H 'Content-Type: application/json' --data-binary @- \
  http://localhost/config/apps/http/servers/preview/routes/0
curl -fsS http://127.0.0.1:18080/p/example/
```

Use one operator writer, or Caddy ETag / If-Match for concurrent changes. The example path strips the prefix; root-relative assets, cookies, WebSockets with absolute paths and redirects may require app base-path support. For arbitrary applications prefer SSH local forwarding with their own origin. Different path routes share one browser origin. Never co-host mutually untrusted previews with credentials. Use isolated browser profiles or origins, or SSH. Use an approved, unused Tailscale Serve HTTPS port (example 8446) pointing to http://127.0.0.1:18080, after checking `tailscale serve status --json` and Tailnet ACL. Do not overwrite existing routes; do not enable Funnel. Without explicit approval, only the SSH path is available. Publication is not implicit in instance creation.

Remove a route before destroying/reusing the instance address:
```sh
sudo curl -fsS --unix-socket /run/neko7-preview/admin.sock -X DELETE http://localhost/id/example-preview
```
A gateway restart discards all ephemeral routes; default is 404. Stop sharing immediately when target identity cannot be continuously confirmed; on any uncertain lifecycle event restart the gateway before sharing again. Never grant route administration to an agent. Do not retain routes across IP reuse. There is no automatic agent publication, TTL, endpoint registry or cross-origin safety guarantee. Native Caddy route inventory is the source of truth.

## Personal data workloads (independent Incus VM artifacts)

Syncthing and Immich have independent pinned build-only image/system outputs and standalone NixOS service tests. Immich uses the reviewed existing unstable pin rather than permitting insecure stable packages. Inspect with `just images`; build `nix build --no-link .#neko7-syncthing-image .#neko7-immich-image`. Do not import/launch these images with real data, enroll guest identities, or perform VM updates/backups/restores until the exact-image lifecycle and hardware gates in the follow-up pass. No live migration or publication is approved.

## Future identity and transport boundaries

Use an authenticated overlay as the transport access boundary, not as application authorization. Keep the physical-uplink deny rule independent of the selected overlay; explicitly admit a new authenticated virtual interface/transport after its crypto, peer identity, key lifecycle, routing, firewall and failure tests. FEC/reliability alone does not supply a secure mesh, encryption or NAT traversal. Do not replace Tailscale with a direct UDP listener or widen the uplink rule for SplitCast without evidence and approval. The supplied Flestr source implements authenticated pairwise media transport with Noise IK and TURN-less ICE, not a routed overlay. Existing outbound UDP/conntrack semantics can support mutually initiated ICE without opening an inbound application port. See [Flestr ingress review](flestr-ingress.md) for exact source boundaries, caveats and new generic UDP test. Flestr integration belongs to SplitCast.

For future MCP/API/website auth, separate OAuth/OIDC authorization server (e.g. Auth0), resource server (MCP/app), application authorization policy and tunnel edge (e.g. Cloudflare). A valid access token must match issuer, audience/resource, expiry and scope, not merely arrive from a mesh IP. Do not commit client secrets. A public Cloudflare tunnel creates externally reachable ingress even without an open port. It requires a separately approved exception to the current Tailnet-only policy. Private WARP/Access paths also need an explicit trust decision. No public edge, identity service, tenant or credential is provisioned here.

T3 remains one existing control plane; no speculative per-agent sandbox is activated. Future worker identities should separate session state from execution credentials, offer restricted native backends, and preserve provider/tool/worktree workflows with positive and negative integration tests. The existing admin user is not a sandbox boundary.

## Repository organization

Keep the native feature selection API and numbered directories. Host placement and physical resource inventory stay in `00-hosts`; flake/evaluation/check plumbing in `10-foundations`; independent workload artifacts in `40-workloads`; reusable native features in `50-features` (hardware, networking, containers, monitoring, development). Separate immutable Nix store from mutable workload state and operator secrets; avoid inventing another module DSL. The changes are limited to the compute platform and do not reorganize unrelated hosts. The host's feature list is grouped by physical machine, ingress, execution, control plane/telemetry, workload placement and common environment without changing the typed API. CI boots the native service modules on NixOS fixture VMs and probes local readiness and external TCP denial, separately from the Incus image builds. Exact-image nested Incus lifecycle, update and isolated restore remain follow-up acceptance gates.
