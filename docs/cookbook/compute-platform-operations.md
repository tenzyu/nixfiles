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

Open http://localhost:13000/d/neko7-platform/. Grafana provides a read-only viewer. The configuration creates no default administrator or public listener. Any local host user can read local telemetry; this is not an isolation boundary between agents. Prometheus scrapes every 30 seconds. It retains data for 7 days and targets a retention size of 2 GB. The write-ahead log and head block use additional space. Incus metrics use a distinct local read-only HTTPS listener without client auth; the management API retains its certificate authentication. The metrics scrape accepts the local self-signed certificate; never apply that exception to a remote host. GPU data requires the actual NVIDIA driver/device. Systemd system units, endpoint probes and Incus instance labels are native inventory. User-unit details, journals, historical GPU per-process data and runtime route inventory are not unified; inspect `journalctl --user`, `journalctl -u UNIT`, `incus monitor`, and native Caddy API below. No unauthenticated telemetry listener is opened to Tailnet or LAN. Do not add a public proxy for Grafana or Prometheus.

## Generic preview gateway

For an app that requires the browser's origin root, an authorized SSH client should use `ssh -N -L 18081:GUEST_IP:APP_PORT neko7`; browser http://localhost:18081/. An SSH SOCKS forward (`ssh -N -D 127.0.0.1:1080 neko7`) is also available for an authorized client; it is not a new host listener or an agent-specific proxy.

For a short, supervised, operator-approved HTTP sharing session only, use the native Caddy API. Never publish an ephemeral agent instance to a less-trusted audience via an IP-only route; use SSH instead. Loopback permission is not an upstream allowlist. This is not an autonomous publication controller. The gateway binds only loopback TCP 18080 and is cgroup-restricted to local/Incus lab addresses. Root or the service account owns the admin socket. Never grant agents unrestricted access to the Caddy admin API, even if they can request a preview. This is a separate proxy process, not the authentication gateway for production. No route is installed at boot. Confirm the instance identity and application port. Substitute the instance IP address and a unique name in the following example:

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

Use one operator writer. For concurrent changes, use Caddy's `ETag` and `If-Match` headers. The example path strips the prefix; root-relative assets, cookies, WebSockets with absolute paths and redirects may require app base-path support. For arbitrary applications prefer SSH local forwarding with their own origin. Different path routes share one browser origin. Never co-host mutually untrusted previews with credentials. Use isolated browser profiles or origins, or SSH. Use an approved, unused Tailscale Serve HTTPS port (example 8446) pointing to http://127.0.0.1:18080, after checking `tailscale serve status --json` and Tailnet ACL. Do not overwrite existing routes; do not enable Funnel. Without explicit approval, only the SSH path is available. Publication is not implicit in instance creation.

Remove a route before destroying/reusing the instance address:
```sh
sudo curl -fsS --unix-socket /run/neko7-preview/admin.sock -X DELETE http://localhost/id/example-preview
```
A gateway restart discards all ephemeral routes. Without a matching route, Caddy returns HTTP 404. Stop sharing immediately when target identity cannot be continuously confirmed; on any uncertain lifecycle event restart the gateway before sharing again. Never grant route administration to an agent. Do not retain routes across IP reuse. There is no automatic agent publication, TTL, endpoint registry or cross-origin safety guarantee. Native Caddy route inventory is the source of truth.

## Personal data workloads (independent Incus VM artifacts)

Syncthing and Immich have independent pinned build-only image/system outputs and standalone NixOS service tests. Immich uses the reviewed existing unstable pin rather than permitting insecure stable packages. Run `just images` to list the images. Build them with `nix build --no-link .#neko7-syncthing-image .#neko7-immich-image`. Do not import/launch these images with real data, enroll guest identities, or perform VM updates/backups/restores until the exact-image lifecycle and hardware gates in the follow-up pass. No live migration or publication is approved.

## Future identity and transport boundaries

The [identity and transport design](compute-platform-design.md#future-identity-and-transport-boundaries) describes the requirements for future changes.

## Repository organization

See the [repository layout for the compute platform](compute-platform-design.md#repository-organization).
