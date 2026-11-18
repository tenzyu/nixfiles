# Individual game server features on neko7

The host now chooses `game-ark = false`, `game-rust = false`, `game-minecraft = true`, and `game-server-tools = true` independently under `local.features`. Only the Minecraft container is declared for neko7, and `game-srv.enable = true` selects its `/srv/minecraft` data root. The existing `configurations.nixos.neko7.module` / `local.features.<name>.enable` declaration API remains unchanged.

- The old `game-server-containers` feature is a **compatibility shim**, not selected on neko7. It still expands to all game capabilities with `lib.mkDefault` (explicit per-game `false` can override this), retaining old NAT behavior for existing callers.
- `game-srv` controls the storage layout (world data at `/srv/minecraft`, service HOME under `/var/lib/game-containers/minecraft`). The 2026-11-18 [cutover record](game-server-srv-migration.md) reports a completed copy, player login, and generation 68 boot entry; it does not prove current uptime.
- `game-server-tools` only installs the `game` CLI, independent of server deployment. When targeting a disabled game, CLI commands cannot start a non-existent container; selection is explicit.
- The host itself owns `networking.nat.externalInterface = "ens18"`; each selected game module contributes its own veth entry to `networking.nat.internalInterfaces`.
- ARK and Rust remain available as optional feature modules but are not instantiated for neko7; no `neko7-ark` or `neko7-rust` container, game service, or associated veth NAT interface should appear in the evaluated configuration.
- Per-container user IDs, IPs, file paths, port lists, `autoStart`, Tailscale identity and the Minecraft `services.minecraft-servers` integration are preserved for each feature when selected. Disabling ARK/Rust does **not** remove any existing host data directories or old container state from disk.
- `game-ark` and `game-rust` each declare their Steam unfree policy instead of relying on the shared bundle flag. The compatibility feature retains its original policy for legacy callers.
- A `game-srv` state change needs an offline data inventory; do **not** run the historical first-cutover copy on an already populated `/srv/minecraft`.
- Source-only evaluation does not prove that an existing container restarts safely or that backups and game updates are transactional. Those operations still require separate validation.

## Review

Run `nix run .#framework-test` and evaluate `nixosConfigurations.neko7.config.system.build.toplevel.drvPath`. Confirm that the game-server feature tests report only `neko7-mc`, its veth interface, and `system.stateVersion = "26.05"`; verify ARK/Rust and their veth entries are absent. Before a host switch, independently diff the evaluated container names, UID/GID, bind mounts, network identity, persistent roots, and systemd service names against the active generation. Do not wipe or re-create game-state directories. A rollback is the prior NixOS generation; it does not reverse any out-of-band SteamCMD game update.
