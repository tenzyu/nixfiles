# Personal compute platform

## Contract

NixOS owns the host substrate, Incus owns dynamic instances, and T3 Code owns agent sessions and projects. The Incus `lab` project is a shared execution permission boundary, not a T3 project or knowledge partition. No repository name is embedded in it. No custom scheduler, registry, governor or execution API. Use native systemd/Nix for finite jobs and NixOS tests for reproducible multi-machine evidence; use Incus for interactive or persistent environments.

Incus uses a directory pool on the existing filesystem (no repartition, migration, or new filesystem). Its default project is operator-only; the restricted lab project has a separate NAT bridge, managed volumes and no arbitrary host disk, GPU, proxy, privileged container or raw VM attachment. This does not provide network egress isolation from the rest of the host/LAN, per-agent identity, or a security sandbox for an agent already running as an administrator. Both projects share physical CPU, memory and I/O. No workload quotas or automatic VM memory overcommit are configured; inspect PSI, available memory, disk and OOM logs before unusually large experiments.

Native preseed is declarative for the pool, bridges, project and default profile; it merges on daemon initialization/restart, not a continuous reconciliation loop. Do not edit these definitions independently or use the default profile as a per-application configuration. Runtime-created instances and custom profiles remain Incus-owned. A soft Incus daemon restart is intended to preserve running guests; a host reboot still stops everything.

Existing T3, Minecraft, builder, SplitCast and Docker services stay in place. No data is moved. Future services can use the operator project without changing the host or T3. Existing application-specific configuration is not a precedent for adding project-specific infrastructure.

## Before approved activation

- Check `ip -4 route`, `ss -ltn`, and existing Incus state. The proposed bridge ranges are 10.77.40.0/24 and 10.77.41.0/24; API port 8443 is loopback-only. Abort on overlap, existing incompatible storage pool, or port conflict. Do not reinitialize an existing Incus installation blindly.
- Confirm `/dev/kvm`, available memory and filesystem space. The operator has reported past MicroVM success; that is not an Incus acceptance result.
- Review the nftables transition: native Incus requires nftables with the NixOS firewall. Verify existing Minecraft NAT, Tailscale, SSH, T3 HTTPS and rootless Docker connectivity after activation. Use an out-of-band Proxmox console and retain the previous generation.
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

Run these as the enrolled user, including from an existing T3 project shell. Select a trusted image and pin its fingerprint for reproducible tests. Names below are examples; choose unique names per session.

```sh
incus image list images: debian/13
incus launch images:debian/13 lab:experiment --ephemeral
incus exec lab:experiment -- sh
incus file push ./artifact lab:experiment/tmp/artifact
incus stop lab:experiment
incus list lab:

incus launch images:debian/13 lab:machine-a --vm --ephemeral
incus launch images:debian/13 lab:machine-b --vm --ephemeral
incus exec lab:machine-a -- sh
incus exec lab:machine-b -- sh
incus stop lab:machine-a
incus stop lab:machine-b
```

Use `incus exec --user UID --group GID --cwd /home/USER` when an ordinary guest user is needed; create that account using the guest's own configuration. Incus VM exec needs a functioning guest agent. External aliases and image downloads are not CI fixtures. Persistent instances omit `--ephemeral`; managed volumes can survive instance removal if deliberately created separately. Stopping an ephemeral instance deletes it, so export required evidence first.

An HTTP preview can listen on its instance address; discover it with `incus list lab:`. For remote browser access, an operator/client can use an existing SSH connection with local forwarding to that private address (for example `ssh -N -L 18080:INSTANCE_IP:8080 neko7`). Do not add public proxy listeners automatically. The repository owns its build/start/test command and guest image if special dependencies are needed; the host does not. NixOS tests may instantiate any number of declarative guests without installing a project-specific host feature.

## Operations and dashboard

Operator: `sudo incus list --all-projects`, `sudo incus info INSTANCE --project PROJECT`, `sudo incus monitor`, `systemctl --failed`, `systemd-cgtop`, and `tailscale serve status`. The bundled Incus UI is served on the loopback API: use `ssh -N -L 8443:127.0.0.1:8443 neko7`, then open https://localhost:8443/ui/ and authenticate using an explicitly enrolled browser certificate. Verify the server fingerprint; do not publish this API via Funnel. The UI shows Incus instances, not health of all native services or automatic preview links. A single service portal across unrelated runtimes remains a separate product-selection decision; no parallel registry is introduced.

## Evidence and recovery

CI builds the pinned native module, imports locally built NixOS guest images, enrolls a restricted client, launches a persistent and ephemeral guest, proves guest-user execution, file separation and HTTP reachability, rejects unauthorized operations, checks cleanup and daemon restart independence. A nested VM runner without working KVM fails rather than claiming VM evidence. CI does not establish actual host firewall coexistence, GPU parity, WAN behavior or physical performance.

On failed host acceptance, retain logs and use the previous NixOS generation through the approved console/recovery procedure. Disabling the feature does not migrate/delete Incus instance data; stop or export instances first. Do not remove `/var/lib/incus` or repeat initialization as a recovery shortcut.
