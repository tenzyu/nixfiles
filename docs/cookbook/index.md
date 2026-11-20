# Cookbook — operate and verify

This is the **human-facing** layer. Start with a safe read-only recipe; destructive or service-affecting operations need their own evidence and explicit operator approval. Git configuration, builds and booted runtime are separate states.

## Work on the configuration

- [Inspect safely](inspect.md) — identify hosts, evaluate a derivation and distinguish read-only from activation.
- [Change a host](change-host.md) — minimal change, focused tests and review boundaries.
- [PR validation](ci-validation.md) — what GitHub CI checks, and what it does not check.
- [Trust boundary](nix-trust-boundary.md) — substituters, builder identities and daemon privilege.

## Persistent state and services

- [Secrets and Tailscale](secrets-and-tailscale.md) — provider, identity and service credential boundaries.
- [Minecraft and game server features](game-server-features.md) · [historical /srv migration](game-server-srv-migration.md) · [service layout](service-layout.md) — do not replay an initial migration on migrated data.
- [Parsec settings review](../../assets/parsec-activation/README.md) — check saved decoder, display and controller settings before a separate manual edit.
- [Nix store cleanup](nix-store-clean.md) · [Home Manager data migration](../../assets/home-layout/README.md) — review result roots or inventory Home routes before separately approved mutations.
- [OpenCode development shells](opencode-devshells.md) · [OpenCode migration](opencode-neko7-migration.md) · [T3 Code](t3code-neko7.md) — remote development and single-writer service migration.
- [QEMU guest](qemu-guest.md) · [SplitCast consumer](splitcast-consumer.md) — host integration versus upstream product ownership.
- [osu! display experiments](../../scripts/osu-performance/README-display.md) · [latency lab](../../scripts/osu-performance/README-lab.md) — experimental evidence, not physical latency proof.

For architectural reasons and rejected alternatives see [LLM Wiki](../memory/index.md); for work not yet accepted see [Roadmap](../../ROADMAP.md).
