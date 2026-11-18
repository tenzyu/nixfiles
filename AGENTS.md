# Agent entrypoint

Use [MEMORY.md](MEMORY.md) to select a task-specific route into the [LLM Wiki](docs/memory/index.md); verify claims against current source and dated evidence. Do not preload the entire documentation tree.

Preserve the typed host `configuration.nix` authoring interface, explicit feature lists, native NixOS/Home Manager semantics and existing successful behavior. [Decisions](docs/memory/decisions.md).

Run focused tests in the **already active** direnv environment. A green CI result is not host acceptance. Never switch/boot/reboot hosts, migrate or delete data, alter secrets, publish services, or merge PRs without explicit approval.
