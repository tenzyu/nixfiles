# Execution capability contract

Read the execution contract with `cat /etc/neko7/execution.md`. Login shells also expose `NEKO7_EXECUTION_GUIDE`. The contract applies to every agent frontend and repository. Run `neko7-capabilities` from any working directory to probe user systemd, the Nix store, rootless Docker, authenticated Incus `lab`, and advertised instance drivers. The probes are read-only, bounded, and run with the current identity. The presence of `/dev/kvm` or an advertised VM driver does not establish native KVM acceptance. An actual launch and workload test are still required.

| Need | Native execution interface | Live discovery |
| --- | --- | --- |
| finite job in current authority | systemd-run --user --wait --collect | systemctl --user status; systemd-cgtop |
| reproducible shell/build | nix develop; nix build | nix flake show; nix config show |
| interactive isolated Linux container | incus launch IMAGE lab:NAME --ephemeral | incus remote list; incus list lab:; incus image list lab: |
| distinct kernel / machine | neko7-lab-vm NAME IMAGE | incus info lab:NAME; test -c /dev/kvm (host only) |
| guest login / file exchange | incus exec lab:NAME -- COMMAND; incus file push | incus info lab:NAME |
| reproducible multi-machine topology | repository-owned NixOS test | nix flake show; nix build -L .#checks.x86_64-linux.NAME |
| OCI application | existing rootless docker | docker info; docker context ls |
| HTTP preview | SSH local forward; operator-approved private Caddy route | incus list lab:; ss -ltn (local) |
| host resource pressure | /proc/pressure/{cpu,memory,io}; free; df | systemd-cgtop |
| operator telemetry | loopback Grafana on 13000, Prometheus 9090 | ssh local forwarding; no public listener |

Containers share host CPU, RAM, and disk without default allocation caps. The installed VM command derives guest-visible capacity from the host and actual storage pool. It does not reserve capacity or automatically resize memory or disk. Use explicit native Incus overrides only for intentional special cases.

If the required command, authenticated remote, image, or permission is unavailable, stop. A feature description is not proof that the current agent identity has permission. Obtain explicit approval before you use `sudo`, request admin certificates, alter Tailnet routes, start public tunnels, modify real data, or deploy permanent services. Incus deletes an ephemeral instance when it stops. Export required results first. The operator must authorize preview endpoint publication separately from VM creation. Shared lab credentials are not per-agent isolation. Do not assume GPU or physical-device access. Do not use a second registry to track live resources.
