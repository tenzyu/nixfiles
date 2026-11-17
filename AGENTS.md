# Agent entrypoint

Read [MEMORY.md](MEMORY.md) first. Follow its links into [the Wiki](docs/index.md) **only when relevant**. Inspect the real Nix module and exact host selection before assuming feature state. Do not preload all docs or histories.

The user values a comprehensible, minimal native-Nix configuration, remote development on neko7 and consumer-only usage on neko5. Preserve the numbered folder categories, known osu! Direct Scanout success, explicit approval boundaries, and existing runtime until migration checks prove parity. Treat neko6 as a removable candidate, not a license to erase unreviewed state.

**Non-negotiable configuration UX:** Preserve the existing host `configuration.nix` syntax: `configurations.nixos.<host>.module`, `local.features.<name>.enable`, and `local.users.<name>.features.<name>.enable`. Do **not** replace it with explicit `imports` or a host-side module list. Preserve nixd/editor completion, option typing, override semantics and user/system feature behavior. Remove opaque bundle/profile chains so host-selected features are directly visible; simplify or replace only the internal discovery/materialization machinery behind this stable interface. Keep personal `tenzyu` implementations separately owned without changing the host authoring experience.

For a code change: define the required observed behavior and non-goals, prune unnecessary work, implement the smallest compatible diff, run the narrowest meaningful validation, document failures, and deliver a PR with exact evidence. A green CI check is not proof of activation or physical acceptance. Do not invent machine observations, credential availability, test results or cache hits.

When the development shell is already loaded via direnv, invoke its normal commands directly rather than wrapping every command in `nix develop -c`. Avoid unsolicited additions of tools, daemons, repositories, abstractions or documentation.
