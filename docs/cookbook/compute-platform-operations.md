# Operate the compute platform dashboard and preview gateway

## Resource ownership

See [compute platform resource ownership](compute-platform-design.md#resource-ownership). Do not manage the same live resource with two tools.

## Dashboard and observability

Use an existing authenticated SSH connection over the Tailnet. Do not use Funnel. Run:

```sh
ssh -N -o ExitOnForwardFailure=yes \
	-L 13000:127.0.0.1:13000 \
	-L 9090:127.0.0.1:9090 \
	-L 8443:127.0.0.1:8443 \
	-L 18080:127.0.0.1:18080 \
	-L 3773:127.0.0.1:3773 neko7
```

Open http://localhost:13000/d/neko7-platform/. Grafana provides a read-only viewer. The configuration creates no default administrator or public listener. Any local host user can read local telemetry; this is not an isolation boundary between agents. Prometheus scrapes every 30 seconds. It retains data for 7 days and targets a retention size of 2 GB. The write-ahead log and head block use additional space. Incus metrics use a distinct local read-only HTTPS listener without client auth; the management API retains its certificate authentication. The metrics scrape accepts the local self-signed certificate; never apply that exception to a remote host. GPU data requires the actual NVIDIA driver/device. Systemd system units, endpoint probes, and Incus instance labels come from native inventory. The dashboard includes allocated project resource counts, physical storage pool used and remaining, instance resident memory, and OOM events from the native Incus exporter. User-unit details, journals, historical GPU per-process data and runtime route inventory are not unified; inspect `journalctl --user`, `journalctl -u UNIT`, `incus monitor`, and native Caddy API below. No unauthenticated telemetry listener is opened to Tailnet or LAN. Do not add a public proxy for Grafana or Prometheus.

## Generic preview gateway

For an app that requires the browser's origin root, an authorized SSH client should use `ssh -N -L 18081:GUEST_IP:APP_PORT neko7`; browser http://localhost:18081/. An SSH SOCKS forward (`ssh -N -D 127.0.0.1:1080 neko7`) is also available for an authorized client; it is not a new host listener or an agent-specific proxy.

For a short, supervised, operator-approved HTTP sharing session only, use the native Caddy API. Never publish an ephemeral agent instance to a less-trusted audience via an IP-only route; use SSH instead. Loopback permission is not an upstream allowlist. This is not an autonomous publication controller. The gateway binds only loopback TCP 18080 and is cgroup-restricted to local addresses and both Incus private bridges (`default` and `lab`). Root or the service account owns the admin socket. Never grant agents unrestricted access to the Caddy admin API, even if they can request a preview. This is a separate proxy process, not the authentication gateway for production. No route is installed at boot. Confirm the instance identity and application port. Substitute the instance IP address and a unique name in the following example:

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

Use one operator writer. For concurrent changes, use Caddy's `ETag` and `If-Match` headers. The example path strips the prefix; root-relative assets, cookies, WebSockets with absolute paths and redirects may require app base-path support. For arbitrary applications, use a distinct host route over the SSH-forwarded gateway or direct SSH local forwarding. Replace the JSON match and handle in the example above with `match:[{host:["example.localhost"]}], handle:[{handler:"reverse_proxy",upstreams:[{dial:$dial}]}]` without a rewrite. Open http://example.localhost:18080/ on the SSH client. Use a unique DNS label for each instance. Confirm that the client resolves it to loopback. Verify the Host match and unknown-host HTTP 404 with `curl` before using the browser. A host route preserves root-relative paths and provides a separate browser origin without a new DNS service or public listener. Host routing is for authorized SSH clients. It does not provide Tailscale Serve wildcard routing or automatic publication. Different path routes share one browser origin. Never co-host mutually untrusted previews with credentials. Use isolated browser profiles or origins, or SSH. Use an approved, unused Tailscale Serve HTTPS port (example 8446) pointing to http://127.0.0.1:18080, after checking `tailscale serve status --json` and Tailnet ACL. Do not overwrite existing routes; do not enable Funnel. Without explicit approval, only the SSH path is available. Publication is not implicit in instance creation.

Remove a route before destroying/reusing the instance address:
```sh
sudo curl -fsS --unix-socket /run/neko7-preview/admin.sock -X DELETE http://localhost/id/example-preview
```
A gateway restart discards all ephemeral routes. Without a matching route, Caddy returns HTTP 404. Stop sharing immediately when target identity cannot be continuously confirmed; on any uncertain lifecycle event restart the gateway before sharing again. Never grant route administration to an agent. Do not retain routes across IP reuse. There is no automatic agent publication, TTL, endpoint registry or cross-origin safety guarantee. Native Caddy route inventory is the source of truth.

## Personal data workloads (independent Incus VM artifacts)

Use [instance operations](compute-instances.md) for the short operator command menu and one-file workload addition. The native commands below explain the lower-level mechanism; do not run both creation paths for the same instance. Immich uses the existing pinned unstable NixOS guest (3.4.1) because stable 2.x is marked insecure/EOL. No vulnerability allowlist.

Both images are built from the pinned NixOS native service and VM image modules. They are not started on host activation. Each has an independent kernel, disk and service identity, disabled SSH and locked root login; access through the operator Incus agent. No host mounts, auth keys, public exposure, default credentials or live data migration. Syncthing starts with no declared devices/folders, global/local discovery, relay and NAT traversal disabled. Immich starts CPU-only with local PostgreSQL + vectorchord and Redis UNIX sockets, ML disabled initially. The web UI binds guest loopback. Normal creation derives guest-visible capacity from the host and pool; no workload-specific sizing is required. Physical resources remain shared; see the instance operations resource semantics.

```sh
just new syncthing syncthing
just new immich immich
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

The [identity and transport design](compute-platform-design.md#future-identity-and-transport-boundaries) describes the requirements for future changes.

## Repository organization

See the [repository layout for the compute platform](compute-platform-design.md#repository-organization).
