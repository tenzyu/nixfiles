# Cookbook for operation and verification

Start with a read-only procedure. Destructive or service-affecting operations need their own evidence and explicit operator approval. Git configuration, builds and booted runtime are separate states.

## Work on the configuration

- [Native operator interface](operator-interface.md) covers feature navigation, store inventory, safe GC, generations, services and workloads.

- [Inspect safely](inspect.md) explains how to identify hosts, evaluate a derivation and distinguish read-only commands from activation.
- [Change a host](change-host.md) covers minimal changes, focused tests and review requirements.
- [PR validation](ci-validation.md) documents the scope and limits of GitHub CI.
- [Trust boundary](nix-trust-boundary.md) covers substituters, builder identities and daemon privilege.

## Persistent state and services

- [Secrets and Tailscale](secrets-and-tailscale.md) defines provider, identity and service credential boundaries.
- [Minecraft and game server features](game-server-features.md) · [historical /srv migration](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/cookbook/game-server-srv-migration.md) · [service layout](service-layout.md). Do not replay an initial migration on migrated data.
- [Parsec settings review](../../assets/parsec-activation/README.md) explains how to check saved decoder, display and controller settings before a separate manual edit.
- [Nix store cleanup](nix-store-clean.md) · [Home Manager data migration](../../assets/home-layout/README.md). Review result roots or inventory Home routes before separately approved mutations.
- [HOME maintenance decision](../adr/0003-home-layout-reuse-first.md). Prefer native app settings and tolerate harmless drift rather than imposing a global HOME authority. Keep existing migration safeguards until independently retired.
- [Switch without moving HOME data](home-migration-rollout.md) describes how to run the Home Manager pre-switch check on each host, resolve refusals and switch one host at a time.
- [OpenCode development shells](opencode-devshells.md) · [OpenCode migration](opencode-neko7-migration.md) · [T3 Code](t3code-neko7.md). These cover remote development and single-writer service migration.
- [Personal compute platform](compute-host.md) covers dynamic restricted instances, host acceptance and native execution.
- [Instance operations](compute-instances.md) covers releases, inventory, restricted lab execution, and persistent VM lifecycle procedures. Native KVM acceptance remains mandatory.
- [Flestr ingress](flestr-ingress.md) documents the transport boundary and UDP test evidence.
- [Compute platform operations](compute-platform-operations.md) covers dashboards, the preview gateway, independent personal-data workloads and resource ownership.
- [Existing workload migration](compute-workload-migration.md) covers independent Minecraft, T3 and SplitCast release profiles and cutover.
- [QEMU guest](qemu-guest.md) · [SplitCast consumer](splitcast-consumer.md). These distinguish host integration from upstream product ownership.
- [neko5 desktop and Gamescope](neko5-desktop.md) describes current presentation policy. The [archive](../archive/README.md) retains earlier experiments.

See the [architecture and decisions](../memory/index.md) for design rationale and rejected alternatives. See the [roadmap](../../ROADMAP.md) for work that still requires acceptance.
