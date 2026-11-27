# Remote execution MCP admission experiment

**Diagnostic only. Do not deploy or merge this branch as an implementation.** The public endpoint and native host execution are not admitted. The [research log](research.log) records the measured results and rejected dependency override.

## Repeat the local transport experiment

Use a disposable Linux VM, with no production mounts, credentials, public listeners or management sockets. Copy these files to its private writable directory. The manifest pins direct dependencies only; the original lock was not retained. Record the newly generated lock and audit results. Do not run this on the production host.

```sh
npm install --ignore-scripts
npm audit --omit=dev
mkdir -p home/.claude-server-commander
printf '{"telemetryEnabled":false,"allowedDirectories":[],"blockedCommands":[]}\n' > home/.claude-server-commander/config.json
chmod 600 home/.claude-server-commander/config.json
HOME="$PWD/home" ./node_modules/.bin/supergateway \
  --stdio "$PWD/node_modules/.bin/desktop-commander" \
  --outputTransport streamableHttp --stateful \
  --host 127.0.0.1 --port 18991 >gateway.log 2>&1 &
gateway_pid=$!
trap 'kill "$gateway_pid" 2>/dev/null || true' EXIT
sleep 2
timeout 40s node probe.mjs
```

The audit is expected to fail for the measured vulnerable graph. The transport test is independent diagnostic evidence, not a replacement for the dependency gate. The probe uses fixed, short commands and a loopback fixture port. Stop the entire VM after the test; the probe's cleanup does not prove child-process cleanup under all disconnection cases.

## Candidate native composition

Reuse the existing Incus substrate. The current shared lab is insufficient because it permits host/LAN egress. Prefer an operator-owned unprivileged guest, dedicated private network, no host mounts or management credentials, and a non-root service identity. Retain independent Nix store and daemon trust. No host Nix daemon socket or Incus socket. Keep tunnel credentials on the operator side, not in the guest. Use native systemd service lifecycle, not an agent scheduler. Do not expose the guest gateway on the uplink. For the private host-to-guest origin path, reject requests from every other source and test bypass denial. Network policy must also deny guest access to the host and other production/private networks, including IPv6, while admitting necessary public package and Git traffic. The existing lab network is not proof of this invariant.

Choose native resource policy from actual host headroom and existing workloads, not a guessed fixed allocation. Worktrees isolate checkouts, not credentials or mutually adversarial agents. Use independent guest identities when trust differs.

Cloudflare Access Managed OAuth terminates client authorization. Use an exact application audience, exact authorized user policy, exact client redirect URI(s), short access tokens and bounded refresh grants. One-time PIN is an optional identity provider. Require `originRequest.access.required` with the intended team and audience in cloudflared, and test missing, invalid and wrong-audience assertions. No bypass policy or alternate unauthenticated origin route. A Cloudflare Access token and a gateway MCP session ID are distinct. An already running process may survive token revocation; emergency revocation must also stop the gateway/guest when needed. Test both new requests and existing streams. Never put Cloudflare or host credentials in this repository or the execution guest.

## Admission order

1. Resolve dependency audit and schema compatibility, retain exact lock, build pinned Nix package without network fetches at service startup. Verify actual package and disabling unintended telemetry/browser downloads.
2. Prove native guest boundary in an isolated fixture before enabling a host feature. Verify no host credentials, production data, management sockets, host/LAN network access or unrestricted Nix daemon. Prove legitimate Git/Nix/Rust/Bun operations, simultaneous worktrees, process cleanup and host resource protection. Use existing native checks; do not relax CI.
3. Build/evaluate the actual host configuration with unchanged gates. Activation is a separate operator approval. Provision an existing free Cloudflare zone and Access configuration only with authorized account access. Do not buy a domain or change plans.
4. After separate activation approval, verify real unauthenticated rejection, OAuth login, refresh, revocation, same-session behavior, and ChatGPT Chat Plus web/Android and Muse invocation. Official ChatGPT full custom MCP documentation does not establish the required consumer Android behavior; the operator's prior OAuth registration is promising but not proof for these tools.
5. Retain evidence for the exact candidate and actual host. Only eligible implementations may integrate; this diagnostic branch is not eligible.

Rollback: stop the dedicated tunnel and gateway, revoke only the associated application grants and credentials, and retain workspace data for operator-reviewed recovery. Never change or stop unrelated services.
