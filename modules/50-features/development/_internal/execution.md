# Execution capability contract

Discover this contract with `cat /etc/neko7/execution.md` (also NEKO7_EXECUTION_GUIDE in login shells). It applies independently of the agent frontend and repository.

| Need | Native execution interface | Live discovery |
| --- | --- | --- |
| finite job in current authority | systemd-run --user --wait --collect | systemctl --user status; systemd-cgtop |
| reproducible shell/build | nix develop; nix build | nix flake show; nix config show |
| interactive isolated Linux container | incus launch IMAGE lab:NAME --ephemeral | incus remote list; incus list lab:; incus image list lab: |
| distinct kernel / machine | incus launch IMAGE lab:NAME --vm --ephemeral | incus info lab:NAME; test -c /dev/kvm (host only) |
| guest login / file exchange | incus exec lab:NAME -- COMMAND; incus file push | incus info lab:NAME |
| reproducible multi-machine topology | repository-owned NixOS test | nix flake show; nix build -L .#checks.x86_64-linux.NAME |
| OCI application | existing rootless docker | docker info; docker context ls |
| HTTP preview | SSH local forward; operator-approved private Caddy route | incus list lab:; ss -ltn (local) |
| host resource pressure | /proc/pressure/{cpu,memory,io}; free; df | systemd-cgtop |
| operator telemetry | loopback Grafana on 13000, Prometheus 9090 | ssh local forwarding; no public listener |

Fail closed if the relevant command, authenticated remote, image or authority is unavailable. A feature description is not proof that the current agent identity has permission. Do not use sudo, request admin certificates, alter Tailnet routes, start public tunnels, touch real data or deploy permanent services without explicit approval. An ephemeral instance is destroyed on stop; export required results first. Preview endpoint publication remains operator-authorized, not implicit in VM creation. Shared lab credentials are not per-agent isolation. Do not assume GPU or physical-device access. Do not use a second registry to track live resources.
