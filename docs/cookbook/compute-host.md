# Operate the personal compute platform

## Contract

Review the [compute host design](compute-host-design.md#contract) before activation. Before a large experiment, inspect pressure stall information (PSI), available memory, disk space, and OOM logs.

## Tailnet-only ingress (host invariant)

Follow the [Tailnet-only ingress policy](compute-host-design.md#tailnet-only-ingress-host-invariant). Never use Funnel or an Internet-facing reverse tunnel. Obtain operator approval before publishing an endpoint.

## Before approved activation

- Check `ip -4 route`, `ss -ltn`, and existing Incus state. The proposed bridge ranges are 10.77.40.0/24 and 10.77.41.0/24; API port 8443 is loopback-only. Abort on overlap, existing incompatible storage pool, or port conflict. Do not reinitialize an existing Incus installation blindly.
- Confirm `/dev/kvm`, available memory and filesystem space. The operator has reported past MicroVM success; that is not an Incus acceptance result.
- Review the nftables transition: native Incus requires nftables with the NixOS firewall. Verify existing Minecraft NAT, Tailscale, SSH, T3 HTTPS and rootless Docker connectivity after activation. From a non-Tailnet uplink peer, confirm application TCP/UDP and forwarded guest connections fail; from a Tailnet peer, confirm SSH/Serve still work. Inspect `sudo nft list table inet tailnet_ingress` and the deny counters. Check the Tailnet policy for Funnel access. Use an out-of-band Proxmox console. Retain the previous generation.
- Build the host closure and pass the CI tests. Only then request explicit approval for activation. Neither merging nor CI results authorize activation.

## Enroll the existing T3 user once

After activation and verification of the daemon, as the normal user on the compute host, export only the public client certificate (the client creates its private key locally if absent):

```sh
umask 077
incus remote get-client-certificate > "$HOME/incus-lab-client.pem"
```

The operator runs the following commands in a separate approved administrative session:

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

Do not grant the agent `incus-admin` or `incus` group access, host socket access, or unrestricted TLS certificates. Never commit client credentials or trust tokens. The T3 process uses the user's ordinary Incus CLI configuration; if it cannot see the client config or executable, inspect its existing systemd environment before changing anything. Verify the certificate's restricted flag and lab project association using `sudo incus config trust list`. Revocation is an operator action via `incus config trust remove <fingerprint>`.

## Native dynamic execution

[Instance operations](compute-instances.md) documents read-only inventory, build-only workload artifacts and ephemeral lab containers. [Flestr ingress](flestr-ingress.md) describes the verified source-level transport boundary; no physical port is opened.

Run these as the enrolled user, including from an existing T3 project shell. Select a trusted image and pin its fingerprint for reproducible tests. Names below are examples; choose unique names per session.

```sh
incus image list images: debian/13
incus launch images:debian/13 lab:experiment --ephemeral
incus exec lab:experiment -- sh
incus file push ./artifact lab:experiment/tmp/artifact
incus stop lab:experiment
incus list lab:

```

Use `incus exec --user UID --group GID --cwd /home/USER` when an ordinary guest user is needed; create that account using the guest's own configuration. Incus VM exec needs a functioning guest agent. External aliases and image downloads are not CI fixtures. Durable VM operations are not admitted by this integration; managed volumes can survive instance removal if deliberately created separately. Before you stop an ephemeral instance, export the evidence you need. Incus deletes the instance when it stops.

An HTTP preview can listen on its instance address; discover it with `incus list lab:`. For remote browser access, an operator/client can use an existing SSH connection with local forwarding to that private address (for example `ssh -N -L 18080:INSTANCE_IP:8080 neko7`). Do not add public proxy listeners. For approved Tailnet HTTP endpoints, use an explicitly authorized Tailscale Serve route to a host-loopback listener; preserve existing Serve routes. Do not use Funnel. The generic Caddy gateway can publish operator-approved ephemeral routes without repository-specific host changes; the repository owns its build/start/test command and guest image if special dependencies are needed. See [platform operations](compute-platform-operations.md). NixOS tests may instantiate any number of declarative guests without installing a project-specific host feature.

## Operations and dashboard

The operator can run `sudo incus list --all-projects`, `sudo incus info INSTANCE --project PROJECT`, `sudo incus monitor`, `systemctl --failed`, `systemd-cgtop`, and `tailscale serve status`. The bundled Incus UI uses the loopback API. Run `ssh -N -L 8443:127.0.0.1:8443 neko7`. Open https://localhost:8443/ui/ and authenticate with an explicitly enrolled browser certificate. Verify the server fingerprint; do not publish this API via Funnel. The UI shows Incus instances, not health of all native services or automatic preview links. The provisioned Grafana overview combines host metrics, systemd health, Incus inventory metrics, optional NVIDIA metrics and endpoint probes; native manager links are available through SSH. Dynamic route inventory remains in Caddy's admin API rather than a duplicate registry. See [platform operations](compute-platform-operations.md).

## Evidence and recovery

CI builds the pinned native module and exercises real container lifecycle, restricted authorization, network reachability, cleanup and daemon restart independence. The separate service module checks and image builds do not prove exact-image Incus VM startup, update or restore. VM lifecycle admission is deferred; the restricted lab permits zero VMs. Do not deploy the personal-data VM images or rely on their recovery paths until the follow-up has passed. Hosted CI does not close actual host firewall coexistence, GPU parity, WAN behavior or physical performance.

On failed host acceptance, retain logs and use the previous NixOS generation through the approved console/recovery procedure. Disabling the feature does not migrate/delete Incus instance data; stop or export instances first. Do not remove `/var/lib/incus` or repeat initialization as a recovery shortcut.
