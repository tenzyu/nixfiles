# Individual game server features on neko7

The host now chooses `game-ark = false`, `game-rust = false`, `game-minecraft = true`, and `game-server-tools = true` independently under `local.features`. Only the Minecraft container is declared for neko7, and the canonical layout selects its `/srv/minecraft` data root. The existing `configurations.nixos.neko7.module` / `local.features.<name>.enable` declaration API remains unchanged.

- The selected game module owns the storage layout (world data at `/srv/minecraft`, service HOME under `/var/lib/game-containers/minecraft`). The 2026-11-18 [cutover record](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/cookbook/game-server-srv-migration.md) reports a completed copy, player login, and generation 68 boot entry; it does not prove current uptime.
- `game-server-tools` only installs the `game` CLI, independent of server deployment. When targeting a disabled game, CLI commands cannot start a non-existent container; selection is explicit.
- The host itself owns `networking.nat.externalInterface = "ens18"`; each selected game module contributes its own veth entry to `networking.nat.internalInterfaces`.
- ARK and Rust remain available as optional feature modules but are not instantiated for neko7; no `neko7-ark` or `neko7-rust` container, game service, or associated veth NAT interface should appear in the evaluated configuration.
- Per-container user IDs, IPs, file paths, port lists, `autoStart`, Tailscale identity and the Minecraft `services.minecraft-servers` integration are preserved for each feature when selected. Disabling ARK/Rust does **not** remove any existing host data directories or old container state from disk.
- `game-ark` and `game-rust` each declare their Steam unfree policy instead of relying on the shared bundle flag. 
- Before enabling a previously disabled game, inventory any earlier data paths; do **not** run the historical first-cutover copy on an already populated `/srv/minecraft`.
- Source-only evaluation does not prove that an existing container restarts safely or that backups and game updates are transactional. Those operations still require separate validation.

The selected Minecraft workload is now built as `.#neko7-minecraft-system` and deployed via the native per-container Nix profile. The machine name, data, identities and backup commands remain unchanged. Seed the incumbent before switching; see [existing workload migration](compute-workload-migration.md).

## Backups and recovery

Use `game diagnose minecraft` to inspect an unconfirmed Minecraft operation. It shows the admission guard, the host and guest unit properties, and the current jobs for each manager. Follow the lock-held recovery procedure before clearing a guard. Inspect archive publication separately before deciding whether to resume a stopped server. [Minecraft backup and recovery runbook](../../modules/50-features/game-servers/_internal/minecraft-backup/README.md#diagnose-and-recover)

ARK and Rust remain disabled on neko7. Their guest units use `SIGINT` for shutdown. A successful systemd stop alone does not establish that each game flushed a restorable save. ARK archives `ShooterGame/Saved`. Rust's guest updater archives the configured identity under `server/`, while the host backup covers the `server/` subtree. Both guest updaters run their own backup and retention before SteamCMD. Reusing the Minecraft admission and publication code would require fixtures for each game's clean stop, archive contents and restore, plus coordination with the independent updater and retention paths. [ARK unit and updater](../../modules/50-features/game-servers/ark.nix), [Rust unit and updater](../../modules/50-features/game-servers/rust.nix), [host backup path](../../modules/50-features/game-servers/_internal/game.sh)

## Review

Run `nix build -L --no-link .#checks.x86_64-linux.framework` and evaluate `nixosConfigurations.neko7.config.system.build.toplevel.drvPath`. Confirm that the game-server feature tests report only `neko7-mc`, its veth interface, and `system.stateVersion = "26.05"`; verify ARK/Rust and their veth entries are absent. Before a host switch, independently diff the evaluated container names, UID/GID, bind mounts, network identity, persistent roots, and systemd service names against the active generation. Do not wipe or re-create game-state directories. A rollback is the prior NixOS generation; it does not reverse any out-of-band SteamCMD game update.
