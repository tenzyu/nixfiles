# Compute platform operations

## Authority, not universal runtime

NixOS owns machine configuration, systemd supervision, KVM/namespace access, drivers, storage mounts, Nix store/GC and firewall. Incus owns dynamically created VM/container instances, profiles, images, volumes and network state. Nix profiles own immutable release pointers for incumbent services. Rootless Docker owns OCI runtime objects; NixOS tests own disposable test topology. None is a second source of truth for another manager's live objects.

OpenTofu is a provider-backed declarative infrastructure plan/apply tool with its own state. It can own operator-managed durable Incus projects/instances or external Cloudflare/Auth0 objects if that becomes useful; do not simultaneously manage those same objects with Incus preseed or manual updates. It does not execute a VM itself. Nixus (infinisil/nixus) is an experimental multi-host NixOS deployment module system; no need to add another host evaluation/deployment abstraction on top of the current flake-parts composition. Neither is a mandatory dependency.

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

Agent default for any origin-root-sensitive app: from a client with existing SSH authorization, `ssh -N -L 18081:GUEST_IP:APP_PORT neko7`; browser http://localhost:18081/. An SSH SOCKS forward (`ssh -N -D 127.0.0.1:1080 neko7`) is also available for an authorized client; it is not a new host listener or an agent-specific proxy.

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

Use one operator writer, or Caddy ETag / If-Match for concurrent changes. The example path strips the prefix; root-relative assets, cookies, WebSockets with absolute paths and redirects may require app base-path support. For arbitrary applications prefer SSH local forwarding with their own origin. Different path routes share one browser origin: never co-host mutually untrusted previews with credentials; use isolated browser profiles/origins or SSH. Use an approved, unused Tailscale Serve HTTPS port (example 8446) pointing to http://127.0.0.1:18080, after checking `tailscale serve status --json` and Tailnet ACL. Do not overwrite existing routes; do not enable Funnel. Without explicit approval, only the SSH path is available. Publication is not implicit in instance creation.

Remove a route before destroying/reusing the instance address:
```sh
sudo curl -fsS --unix-socket /run/neko7-preview/admin.sock -X DELETE http://localhost/id/example-preview
```
A gateway restart discards all ephemeral routes; default is 404. Stop sharing immediately when target identity cannot be continuously confirmed; on any uncertain lifecycle event restart the gateway before sharing again. Never grant route administration to an agent. Do not retain routes across IP reuse. There is no automatic agent publication, TTL, endpoint registry or cross-origin safety guarantee. Native Caddy route inventory is the source of truth.

## Personal data workloads (independent Incus VM artifacts)

Use [instance operations](compute-instances.md) for the short operator command menu and one-file workload addition. The native commands below explain the lower-level mechanism; do not run both creation paths for the same instance. Immich uses the existing pinned unstable NixOS guest (3.4.1) because stable 2.x is marked insecure/EOL. No vulnerability allowlist.

Both images are built from the pinned NixOS native service and VM image modules. They are not started on host activation. Each has an independent kernel, disk and service identity, disabled SSH and locked root login; access through the operator Incus agent. No host mounts, auth keys, public exposure, default credentials or live data migration. Syncthing starts with no declared devices/folders, global/local discovery, relay and NAT traversal disabled. Immich starts CPU-only with local PostgreSQL + vectorchord and Redis UNIX sockets, ML disabled initially. The web UI binds guest loopback. Suggested initial sizing, not enforced globally: Syncthing 2 vCPU/2 GiB, Immich 4 vCPU/6 GiB, adjust disk to verified data requirements. Build, import, initialize; choose a disk size that fits the actual dataset and available space (examples deliberately small for empty instances).

```sh
out=$(nix build --no-link --print-out-paths .#neko7-syncthing-image)
sudo incus image import "$out/metadata.tar.xz" "$out/nixos.qcow2" --alias syncthing-reviewed
sudo incus launch syncthing-reviewed syncthing --vm -c security.secureboot=false -c limits.cpu=2 -c limits.memory=2GiB
out=$(nix build --no-link --print-out-paths .#neko7-immich-image)
sudo incus image import "$out/metadata.tar.xz" "$out/nixos.qcow2" --alias immich-reviewed
sudo incus launch immich-reviewed immich --vm -c security.secureboot=false -c limits.cpu=4 -c limits.memory=6GiB
sudo incus exec syncthing -- systemctl is-active syncthing
sudo incus exec immich -- systemctl is-active immich-server
sudo incus exec immich -- curl -fsS http://127.0.0.1:2283/api/server/ping
```

Inspect the image/instance fingerprint, root disk size and free space before use. Configure guest Tailnet identity with the existing approved enrollment procedure (no duplicate node identity); never enable Funnel. Syncthing peer addresses use approved Tailnet addresses, port 22000; configure device IDs, folders, GUI password and initial synchronization direction explicitly. For GUI and Immich HTTP use approved guest Tailscale Serve with loopback origin; initialize admin from authorized client before exposing more broadly. Do not share media paths or sync PostgreSQL files with Syncthing. No automatic pairing, admin creation, public sharing or external tunnel.

Updates: build `.#neko7-<name>-system` independently. For a stopped-write/maintenance window with verified backup, transfer the complete closure via operator Incus exec (trusted source only):
```sh
candidate=$(nix build --no-link --print-out-paths .#neko7-immich-system)
nix-store --export $(nix-store -qR "$candidate") | sudo incus exec immich -- nix-store --import
sudo incus exec immich -- nix-env -p /nix/var/nix/profiles/system --set "$candidate"
sudo incus exec immich -- "$candidate/bin/switch-to-configuration" switch
```
Confirm guest profile and health; software rollback uses the guest's native system generation, not the host generation. Database migration may make software-only rollback unsafe. Before any real data, rehearse offline `incus stop NAME; incus export NAME /approved/backup/NAME.tar.gz; incus start NAME`; secure backup storage, verify checksum and restore into a **non-networked** isolated instance before considering it a valid backup (do not duplicate the live Tailscale/Syncthing identity). Immich additionally requires coordinated PostgreSQL dump and media backup; restore them together. No automatic deletion/retention of real data. Off-host backup target is not configured. Whole-VM export is the baseline, not a claim that independent data-volume lifecycle or application-consistent restore has been proven.

## Future identity and transport boundaries

Use an authenticated overlay as the transport access boundary, not as application authorization. Keep the physical-uplink deny rule independent of the selected overlay; explicitly admit a new authenticated virtual interface/transport after its crypto, peer identity, key lifecycle, routing, firewall and failure tests. FEC/reliability alone does not supply a secure mesh, encryption or NAT traversal. Do not replace Tailscale with a direct UDP listener or widen the uplink rule for SplitCast without evidence and approval. The supplied Flestr source implements authenticated pairwise media transport with Noise IK and TURN-less ICE, not a routed overlay. Existing outbound UDP/conntrack semantics can support mutually initiated ICE without opening an inbound application port. See [Flestr ingress review](flestr-ingress.md) for exact source boundaries, caveats and new generic UDP test. Flestr integration belongs to SplitCast.

For future MCP/API/website auth, separate OAuth/OIDC authorization server (e.g. Auth0), resource server (MCP/app), application authorization policy and tunnel edge (e.g. Cloudflare). A valid access token must match issuer, audience/resource, expiry and scope, not merely arrive from a mesh IP. Do not commit client secrets. A public Cloudflare tunnel is an externally reachable ingress even without an open port: requires a separate approved exception to the current Tailnet-only policy. Private WARP/Access paths also need an explicit trust decision. No public edge, identity service, tenant or credential is provisioned here.

T3 remains one existing control plane; no speculative per-agent sandbox is activated. Future worker identities should separate session state from execution credentials, offer restricted native backends, and preserve provider/tool/worktree workflows with positive and negative integration tests. The existing admin user is not a sandbox boundary.

## Repository organization

Keep the native feature selection API and numbered directories. Host placement and physical resource inventory stay in `00-hosts`; flake/evaluation/check plumbing in `10-foundations`; independent workload artifacts in `40-workloads`; reusable native features in `50-features` (hardware, networking, containers, monitoring, development). Separate immutable Nix store from mutable workload state and operator secrets; avoid inventing another module DSL. This is a scoped extension, not a wholesale reorganization of unrelated hosts. The host's feature list is grouped by physical machine, ingress, execution, control plane/telemetry, workload placement and common environment without changing the typed API. CI boots the native service modules on NixOS fixture VMs and probes local readiness and external TCP denial, separately from the Incus image builds. Separate exact-image Incus lifecycle checks attempt creation, readiness, independent identity, update, export and isolated restore of each production image. Hosted TCG execution is opt-in diagnostic evidence, not a merge or hardware acceptance substitute; native KVM execution and recorded results are mandatory.
