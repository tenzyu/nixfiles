# Individual game server features on neko7

The host now chooses `game-ark`, `game-rust`, `game-minecraft`, and `game-server-tools` independently under `local.features`. The existing `configurations.nixos.neko7.module` / `local.features.<name>.enable` declaration API remains unchanged.

- The old `game-server-containers` feature is a **compatibility shim**, not selected on neko7. It still expands to all game capabilities with `lib.mkDefault` (explicit per-game `false` can override this), retaining old NAT behavior for existing callers.
- `game-server-tools` only installs the `game` CLI, independent of server deployment. When targeting a disabled game, CLI commands cannot start a non-existent container; selection is explicit.
- The host itself owns `networking.nat.externalInterface = "ens18"`; each selected game module contributes its own veth entry to `networking.nat.internalInterfaces`.
- Per-container user IDs, IPs, file paths, port lists, `autoStart`, Tailscale identity and the Minecraft `services.minecraft-servers` integration have **not changed**.
- `game-ark` and `game-rust` each declare their Steam unfree policy instead of relying on the shared bundle flag. The compatibility feature retains its original policy for legacy callers.
- Source-only evaluation does not prove that an existing container restarts safely or that backups and game updates are transactional. Those operations still require separate validation.

## Review

Run `nix run .#framework-test` and evaluate `nixosConfigurations.neko7.config.system.build.toplevel.drvPath`. Confirm that the game-server feature test reports all three expected containers and native NAT interfaces. Before a host switch, independently diff the evaluated container names, UID/GID, bind mounts, network identity, persistent roots, and systemd service names against the active generation. Do not wipe or re-create game-state directories. A rollback is the prior NixOS generation; it does not reverse any out-of-band SteamCMD game update.
