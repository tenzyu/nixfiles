# Instructions for agents

Use [MEMORY.md](MEMORY.md) to find the relevant [LLM Wiki](docs/memory/index.md) page. Verify claims against current source and dated evidence. Do not preload the entire documentation tree.

Preserve the typed host `configuration.nix` interface, explicit feature lists, native NixOS and Home Manager semantics, and existing behavior. Follow the [configuration decisions](docs/memory/decisions.md).

Run the relevant `checks.x86_64-linux` derivation in the active direnv environment. See the [validation commands](docs/cookbook/ci-validation.md). A green CI result is not host acceptance. Never switch/boot/reboot hosts, migrate or delete data, alter secrets, publish services, or merge PRs without explicit approval.
