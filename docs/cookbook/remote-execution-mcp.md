# Remote execution MCP (admission candidate)

Do not activate this workload on neko7 until its actual Incus, resource, authentication and host-coexistence evidence is accepted. The host feature is opt-in and not enabled on any host. The isolated guest image is a build/test artifact; it must never be attached to the default shared network.

## Verify

```sh
nix build -L --no-link .#remote-execution-mcp-desktop-commander .#remote-execution-mcp-supergateway
nix build -L --no-link .#remote-execution-mcp-container
nix build -L --no-link .#checks.x86_64-linux.remote-execution-mcp
```

The first two packages pin upstream code, exact npm lockfiles and fixed-output cache hashes. The upstream Zod migration is imported from unmerged [Desktop Commander PR #988](https://github.com/wonderwhy-er/DesktopCommanderMCP/pull/988) rather than reimplementing schema conversion. Nix packages the Chromium executable, sets the upstream telemetry disable environment variable and provides empty local feature flags via a data URL. The original browser fallback remains upstream code on other platforms; the Linux package uses the pinned executable.

The native integration check imports the actual NixOS Incus container image, tests the stateful gateway with a standard MCP SDK, verifies Git Worktree isolation, exit 0/7, reconnect, Nix eval/build with sandbox enabled, Rust compilation and Bun execution, tests guest/host/private-prefix reachability, and checks service restart. This is a required additional compute-host check, not a replacement for any existing check.

## Operator boundary

After review, configure `local.features.remote-execution-mcp-network.enable` with a nonoverlapping `local.remoteExecutionMcp.bridgeAddress`. Inventory actual protected routes, including globally numbered LANs, and add them to `local.remoteExecutionMcp.protectedIPv4`. The dedicated Incus profile has no host mounts or management credentials. Only the operator may attach instances to this bridge; do not share it with other workloads. No arbitrary CPU or memory limit is imposed by this candidate. Inspect host PSI, capacity, storage and incumbent workloads before choosing an admission budget and starting the service.

The tunnel credential and daemon run outside the guest as a dedicated host identity (`remote-mcp-tunnel`). The native firewall permits host origin connections to the internal gateway only from that identity and the trusted root operator; forwarded access is blocked. The guest cannot use the host as an arbitrary network destination, access private IPv4 routes or forward via an interface other than the uplink. Guest and host network checks do not establish Cloudflare authentication. Do not attach the tunnel or expose an endpoint until a separate activation approval.

The remaining provider-specific steps require authorized access to the existing Cloudflare account: configure Managed OAuth and a user-specific Access policy, verify the exact JWT audience at cloudflared, disable alternate paths, and test login/refresh/revocation and rejected unauthorized requests from the actual ChatGPT Plus Android and Muse clients. Existing streams and processes must also be tested after revocation. No new public inbound listener, new paid infrastructure or production activation is authorized by this PR.

See [research.log](../../assets/remote-execution-mcp/research.log) for exact source and observed dependency evidence.
