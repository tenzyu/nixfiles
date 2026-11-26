# Independent neko7 workload release design

## Target and authority

The host generation owns hardware, networking, native isolation mechanisms and stable service admission. A workload generation owns application release artifacts. The migration preserves the existing service identities and endpoints. Do not add a custom deployment manager, scheduler or registry; native Nix profiles are the release pointer and rollback mechanism.

| Declared capability | Target boundary | Mutable authority |
| --- | --- | --- |
| Minecraft | Existing native nspawn machine, independently built NixOS system profile | Existing /srv/minecraft, host service account, Tailscale state and lifecycle lock |
| T3 Code | Single native user systemd control plane, independently built T3/Codex runtime profile | Existing HOME, projects, provider auth, database, same 3773 and Serve 8445 |
| SplitCast production | Native manual user unit and TOML produced by the original upstream module, deployed together in an independent profile | Existing HOME credentials, peer settings and host GPU/audio; Rust parity gate remains false |
| Nix builder / SSH / Tailscale / Incus / rootless Docker / NVIDIA | Host or native user services | Existing daemon state, key restrictions and hardware |
| llama-cpp CUDA | Installed CLI, not a declared daemon | No service migration or invented daemon |
| ARK / Rust / OpenCode candidate | Disabled in source | No implicit activation; inspect unmanaged live units separately |

Incus remains the dynamic instance manager for new container/VM jobs and services. There is no project-specific execution adapter. Do not move existing Minecraft into Incus just to standardize the runtime name. Its existing nspawn machine has a production backup contract and separate data ownership. The migration separates its software release from the host generation. Moving T3 into a guest would make the host control plane depend on Incus and require a new management ingress. Keep T3 on the host. No new application or public listener is enabled.

## Evidence

The CI workflow evaluates the actual host and all three artifact derivations, checks that their derivations are not referenced by the host generation, builds each artifact in an independent job, and tests a native nspawn profile upgrade from v1 to v2 and rollback to v1 with persistent state, host-generation identity and an unrelated service PID unchanged. It does not replay live credentials, prove production data/schema rollback, or attest to hardware/media performance. The real deployment gate is the approved first cutover above.

See the [cutover and release procedure](compute-workload-migration.md).
