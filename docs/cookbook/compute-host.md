# Personal compute platform

## Contract

NixOS owns the host substrate, Incus owns dynamic instances, and T3 Code owns agent sessions and projects. The Incus `lab` project is a shared execution permission boundary, not a T3 project or knowledge partition. No repository name is embedded in it. No custom scheduler, registry, governor or execution API. Use native systemd/Nix for finite jobs and NixOS tests for reproducible multi-machine evidence; use Incus for interactive or persistent environments.

Incus uses a directory pool on the existing filesystem (no repartition, migration, or new filesystem). Its default project is operator-only; the restricted lab project has a separate NAT bridge, managed volumes and no arbitrary host disk, GPU, proxy, privileged container or raw VM attachment. This does not provide network egress isolation from the rest of the host/LAN, per-agent identity, or a security sandbox for an agent already running as an administrator. Both projects share physical CPU, memory and I/O. No aggregate admission budget or default container CPU/RAM/disk quota is configured. Containers consume shared host resources on demand. VM creation derives guest-visible CPU count, memory and sparse root block size from the host and actual Incus pool; it is not a reservation or automatic ballooning policy. Concurrent VMs can overcommit physical memory/storage; observe PSI, available memory, disk and OOM logs. A guest-visible maximum is necessary for a distinct kernel and block device; this is not a guarantee of physical capacity or dynamic resizing.

Native preseed is declarative for the pool, bridges, project and default profile; it merges on daemon initialization/restart, not a continuous reconciliation loop. Do not edit these definitions independently or use the default profile as a per-application configuration. Runtime-created instances and custom profiles remain Incus-owned. A soft Incus daemon restart is intended to preserve running guests; a host reboot still stops everything.

All declared existing services are assigned a lifecycle boundary, not grandfathered into the old host-coupled release model. Minecraft, T3 Code and SplitCast now have independent native Nix deployment artifacts and generation profiles. Minecraft deliberately keeps its existing nspawn machine, data, Tailnet identity and backup protocol; converting an already independent machine to Incus would introduce an unnecessary data/identity and backup migration. T3 remains a single user control plane so it can operate Incus without exposing the management API outside loopback. SplitCast retains its pinned upstream manual parity gate and host GPU/audio prerequisites; no production service is started by this migration. The Nix daemon/remote builder, Tailscale, SSH, drivers and rootless Docker are host capabilities, not application releases. See [existing workload migration](compute-workload-migration.md) for the concrete activation and rollback gates. No live data is moved by the PR.

## Tailnet-only ingress (host invariant)

No application listener, public port forward, DMZ, physical NIC passthrough or public reverse tunnel may expose services through neko7's uplink. External access is exclusively authenticated Tailnet access (Serve, SSH forwarding, or a separately approved guest Tailnet identity). Never use Funnel or an Internet-facing reverse tunnel; never publish an endpoint without operator approval. The existing Proxmox/router port-opening prohibition remains unchanged.

The host selects the independent `tailnet-ingress` feature. Its native nftables inet table filters new TCP/UDP input and unsolicited forwarding arriving on the declared NAT uplink (`ens18`), including DNAT to any guest. It leaves loopback, internal interfaces, Tailnet traffic, outgoing connections and their replies unchanged. DHCP client traffic and the existing encrypted Tailscale UDP transport are exceptions to the guard, not new firewall openings; ICMP/control traffic remains governed by the ordinary firewall. The guard is not an outbound filter, and established connections are deliberately preserved. NixOS NAT port forwards and DMZ configuration are rejected at evaluation. Restricted Incus credentials cannot attach a physical NIC, add proxy devices or administer the shared network.

This is a packet-level direct-ingress guard, not a security boundary against host administrators, arbitrary outbound tunnels or changes to Tailnet control-plane policy. Funnel uses outbound connectivity, so nftables cannot reliably distinguish it from legitimate Tailnet traffic. The operator must verify in the Tailnet policy that Funnel capability is not granted to neko7 or guest identities (including broad nodeAttrs selectors), and check `tailscale serve status --json` for any enabled `AllowFunnel` entries on those nodes. Do not modify existing Serve routes or Tailnet policy automatically. Verify other uplinks if hardware/network topology changes.

The separate ingress CI test uses real network namespaces with a deliberately allowed host listener, a routed guest, and deliberate DNAT, checks that the actual drop counters increase, and proves host/internal HTTP and outbound NAT still work. It does not substitute for actual Tailscale connectivity, current Tailnet policy or Proxmox firewall evidence.

## Before approved activation

- Check `ip -4 route`, `ss -ltn`, and existing Incus state. The proposed bridge ranges are 10.77.40.0/24 and 10.77.41.0/24; API port 8443 is loopback-only. Abort on overlap, existing incompatible storage pool, or port conflict. Do not reinitialize an existing Incus installation blindly.
- The previous main/draft quotas are explicitly unset before preseed by native Incus CLI operations, only when the legacy keys are actually present. Project quotas are removed before profile defaults; empty aggregate keys must not be replayed on each preseed because Incus validates them against existing instances. Before approved activation export the existing project/profile configuration, check for unexpected live VMs and instance-specific overrides; after activation verify the lab project and default profile have no resource-limit keys. No existing instance-specific config or disk is resized by this migration.
- Confirm `/dev/kvm`, available memory and filesystem space. The operator has reported past MicroVM success; that is not an Incus acceptance result.
- Review the nftables transition: native Incus requires nftables with the NixOS firewall. Verify existing Minecraft NAT, Tailscale, SSH, T3 HTTPS and rootless Docker connectivity after activation. From a non-Tailnet uplink peer, confirm application TCP/UDP and forwarded guest connections fail; from a Tailnet peer, confirm SSH/Serve still work. Inspect `sudo nft list table inet tailnet_ingress` and the deny counters. Check Tailnet Funnel policy as above. Use an out-of-band Proxmox console and retain the previous generation.
- Build the host closure and pass the CI tests. Only then request explicit approval for activation. Neither merging nor CI results authorize activation.

## Enroll the existing T3 user once

After activation and verification of the daemon, as the normal user on the compute host, export only the public client certificate (the client creates its private key locally if absent):

```sh
umask 077
incus remote get-client-certificate > "$HOME/incus-lab-client.pem"
```

Operator, in a separate approved administrative session:

```sh
sudo incus project show lab
sudo incus config trust add-certificate /home/tenzyu/incus-lab-client.pem --projects lab --restricted
sudo openssl x509 -in /var/lib/incus/server.crt -noout -fingerprint -sha256
```

The last command displays the server fingerprint. As the normal user, enroll the loopback remote and compare the prompted fingerprint to the operator's output before accepting:

```sh
incus remote add lab https://127.0.0.1:8443 --project lab
incus list lab:
```

Do not grant `incus-admin`, `incus` group access, host socket access or unrestricted TLS certificates to the agent. Never commit client credentials or trust tokens. The T3 process uses the user's ordinary Incus CLI configuration; if it cannot see the client config or executable, inspect its existing systemd environment before changing anything. Verify the certificate's restricted flag and lab project association using `sudo incus config trust list`. Revocation is an operator action via `incus config trust remove <fingerprint>`.

## Native dynamic execution

[Instance operations](compute-instances.md) is the short entrypoint for adding, updating, backing up and retiring durable instances and running ephemeral lab instances. [Flestr ingress](flestr-ingress.md) describes the verified source-level transport boundary; no physical port is opened.

Run these as the enrolled user, including from an existing T3 project shell. Select a trusted image and pin its fingerprint for reproducible tests. Names below are examples; choose unique names per session.

```sh
incus image list images: debian/13
incus launch images:debian/13 lab:experiment --ephemeral
incus exec lab:experiment -- sh
incus file push ./artifact lab:experiment/tmp/artifact
incus stop lab:experiment
incus list lab:

neko7-lab-vm machine-a images:debian/13
neko7-lab-vm machine-b images:debian/13
incus exec lab:machine-a -- sh
incus exec lab:machine-b -- sh
incus stop lab:machine-a
incus stop lab:machine-b
```

Use `incus exec --user UID --group GID --cwd /home/USER` when an ordinary guest user is needed; create that account using the guest's own configuration. Incus VM exec needs a functioning guest agent. External aliases and image downloads are not CI fixtures. Persistent instances omit `--ephemeral`; managed volumes can survive instance removal if deliberately created separately. Stopping an ephemeral instance deletes it, so export required evidence first.

An HTTP preview can listen on its instance address; discover it with `incus list lab:`. For remote browser access, an operator/client can use an existing SSH connection with local forwarding to that private address (for example `ssh -N -L 18080:INSTANCE_IP:8080 neko7`). Do not add public proxy listeners. For approved Tailnet HTTP endpoints, use an explicitly authorized Tailscale Serve route to a host-loopback listener; preserve existing Serve routes. Do not use Funnel. The generic Caddy gateway can publish operator-approved ephemeral routes without repository-specific host changes; the repository owns its build/start/test command and guest image if special dependencies are needed. See [platform operations](compute-platform-operations.md). NixOS tests may instantiate any number of declarative guests without installing a project-specific host feature.

## Operations and dashboard

Operator: `sudo incus list --all-projects`, `sudo incus info INSTANCE --project PROJECT`, `sudo incus monitor`, `systemctl --failed`, `systemd-cgtop`, and `tailscale serve status`. The bundled Incus UI is served on the loopback API: use `ssh -N -L 8443:127.0.0.1:8443 neko7`, then open https://localhost:8443/ui/ and authenticate using an explicitly enrolled browser certificate. Verify the server fingerprint; do not publish this API via Funnel. The UI shows Incus instances, not health of all native services or automatic preview links. The provisioned Grafana overview combines host metrics, systemd health, Incus inventory metrics, optional NVIDIA metrics and endpoint probes; native manager links are available through SSH. Dynamic route inventory remains in Caddy's admin API rather than a duplicate registry. See [platform operations](compute-platform-operations.md).

## Evidence and recovery

CI builds the pinned native module, imports locally built NixOS guest images, enrolls a restricted client, launches a persistent and ephemeral guest, proves guest-user execution, file separation and HTTP reachability, rejects unauthorized operations, checks cleanup and daemon restart independence. Hosted CI builds images, runs service and container tests, and evaluates native VM checks. Native KVM lifecycle execution remains mandatory before merge or activation. The retired software-emulation diagnostic did not establish hardware acceptance; [historical source and evidence](https://github.com/tenzyu/nixfiles/tree/5b7c1fea748bf7ee3877703dbef9ecdb738d2e36) remain available. On an approved compatible test host run `nix build -L --no-link .#checks.x86_64-linux.compute-host-vm .#checks.x86_64-linux.incus-workload-syncthing .#checks.x86_64-linux.incus-workload-immich`. Do not run them in the live Incus instance namespace or enroll a privileged persistent runner as a workaround. A green hosted CI does not close hardware acceptance, actual host firewall coexistence, GPU parity, WAN behavior or physical performance.

On failed host acceptance, retain logs and use the previous NixOS generation through the approved console/recovery procedure. Disabling the feature does not migrate/delete Incus instance data; stop or export instances first. Do not remove `/var/lib/incus` or repeat initialization as a recovery shortcut.
