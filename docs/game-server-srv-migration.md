# Minecraft service data: operator-controlled /srv cutover

**neko7 status (2026-11-18):** after an offline copy and player login,
the approved switch made NixOS generation 68 the default boot entry.
Minecraft is running from `/srv/minecraft` with the existing Tailscale
identity. The boot entry was verified on the running host.

The current neko7 configuration enables Minecraft only; ARK and Rust remain
disabled. Their prospective `/srv/{ark,rust}` layouts exist in source but
**must not** be activated against historical data without their own inventory.

## Source, destination, and invariant

| Purpose | Old (must remain intact) | Destination |
| --- | --- | --- |
| Minecraft worlds / server configs | `/home/game-minecraft/minecraft/` | `/srv/minecraft/` |
| Tailscale node identity | `/home/game-minecraft/.state/tailscale/` | `/var/lib/game-containers/minecraft/.state/tailscale/` |
| Existing runtime auth key | `/home/game-minecraft/secrets/` | `/var/lib/game-containers/minecraft/secrets/` |
| Service account HOME | `/home/game-minecraft` | `/var/lib/game-containers/minecraft` |

UID/GID remain 27009. The container remains `neko7-mc`, with
`10.77.30.1/10.77.30.2` networking and existing Tailscale hostname.
`nix-minecraft` uses `services.minecraft-servers.dataDir` and defaults to
`/srv/minecraft`. The opt-in switch removes the `ProtectHome=false`
override, so upstream's `ProtectHome=true` applies.

**Important:** both guest and host must see the same data at the new
`/srv/minecraft` path. The native `containers.neko7-mc.bindMounts` supplies
the read/write bind mount; the path's host owner must match the guest UID
without introducing `privateUsers` remapping. The host's `/srv` must be
mounted before container startup. No activation hook, tmpfiles cleanup, or
program in this PR moves or deletes legacy data.

## Preconditions — inspect, do not migrate yet

From a trusted local/proxmox console or a session with rollback access on neko7:

```bash
sudo test -d /home/game-minecraft/minecraft/survival
sudo test -d /home/game-minecraft/.state/tailscale
sudo test -d /home/game-minecraft/secrets
sudo test ! -e /srv/minecraft
sudo test ! -e /var/lib/game-containers/minecraft
sudo findmnt -T /home/game-minecraft/minecraft
sudo findmnt -T /srv
sudo du -sh /home/game-minecraft/minecraft
df -h /srv /var/lib/game-containers
id game-minecraft
```

**Abort** on a failed test, missing filesystem, insufficient space, unknown
symlink target or UID mismatch. Inspect any symlinks in the old data tree
with `sudo find /home/game-minecraft -type l -ls`. Check that there is no
second Minecraft instance writing to the world. Save an independent
backup or VM snapshot before running the copy.

## TODO(srv-cutover): shortest host operation (requires explicit approval)

Requires `rsync` available on neko7 (install/provide temporarily if absent).
Work from the checked-out PR version; **do not** enable the flag until after
the stopped-container verification.

```bash
# 1. Stop the only writer.
sudo systemctl stop container@neko7-mc.service
sudo systemctl is-active --quiet container@neko7-mc.service && exit 1

# 2. Refuse to overwrite a previously provisioned destination.
sudo test ! -e /srv/minecraft || exit 1
sudo test ! -e /var/lib/game-containers/minecraft || exit 1
sudo install -d -o game-minecraft -g game-minecraft -m 0750 /srv/minecraft
sudo install -d -o game-minecraft -g game-minecraft -m 0750 /var/lib/game-containers/minecraft

# 3. Copy game data and identity, preserving numeric ownership and metadata.
sudo rsync -aHAXS --numeric-ids /home/game-minecraft/minecraft/ /srv/minecraft/
sudo rsync -aHAXS --numeric-ids /home/game-minecraft/.state/ /var/lib/game-containers/minecraft/.state/
sudo rsync -aHAXS --numeric-ids /home/game-minecraft/secrets/ /var/lib/game-containers/minecraft/secrets/

# 4. All three checksum dry-runs must output no changes and exit zero.
sudo rsync -aHAXcni --numeric-ids /home/game-minecraft/minecraft/ /srv/minecraft/
sudo rsync -aHAXcni --numeric-ids /home/game-minecraft/.state/ /var/lib/game-containers/minecraft/.state/
sudo rsync -aHAXcni --numeric-ids /home/game-minecraft/secrets/ /var/lib/game-containers/minecraft/secrets/
```

The backup/identity copy might require the Tailscale daemon itself to stop
in the guest before copying; stopping the container should guarantee no
guest process is writing its bind mounts. Do **not** run the command against
live files.

If the destination already exists, do not use `--delete`, `mv`, or force
overwrite. Treat it as a manual collision/rollback case.

### Commit the final enablement

In `modules/00-hosts/neko7/configuration.nix` change only:

```nix
game-srv.enable = true;
```

Commit the host-selection change in Git (encrypted secrets are outside the
scope of this PR), evaluate, and apply **only after approving the host switch**:

```bash
git add modules/00-hosts/neko7/configuration.nix
git commit -m "feat(neko7): activate verified game /srv layout"
nix eval --raw '.#nixosConfigurations.neko7.config.containers.neko7-mc.bindMounts."/srv/minecraft".hostPath'
sudo nixos-rebuild test --flake .#neko7
sudo systemctl status container@neko7-mc.service
game status minecraft
game ip minecraft
```

Nix attr paths with slashes require quoted selectors; the **canonical**
Nix command is:

```bash
nix eval --raw '.#nixosConfigurations.neko7.config.containers.neko7-mc.bindMounts."/srv/minecraft".hostPath'
```

Check `journalctl -u container@neko7-mc.service` and the guest
`minecraft-server-survival` unit, then verify the existing world loads and
players can connect. Independently confirm the Tailscale node identity (no
new node/duplicate) and that `game backup minecraft` reads the **new**
world path. Run `nixos-rebuild switch` only after this acceptance, then
record the new generation. No public game ports are intended.

## Rollback

- If the new service has **not written** any state, stop it and switch
  back to the old generation; the retained `/home` copy is the rollback.
- If the service **has written** new world/identity state, stop it first
  and reconcile changed data back to the legacy path **before** switching.
  Do not roll back to stale world data, and do not replace auth identity
  files while tailscaled is running.
- Never delete either old data tree until a separate, independently tested
  backup/restore and explicit approval exist.

## Edge cases

- A /srv bind mount mounted after container startup can expose an empty
  directory. Verify `findmnt -T /srv/minecraft` on the host and
  `systemctl list-dependencies --after container@neko7-mc.service`.
- `rsync -a` alone does not preserve hard links, ACLs and xattrs; use
  `-aHAX`. Verify using a checksum dry-run. See the [rsync manual](https://rsync.samba.org/ftp/rsync/rsync.1).
- NixOS `containers.*.privateUsers` is not enabled here; turning it on
  independently requires mapped-UID tests for writable bind mounts.
- `nixos-rebuild test` activates services temporarily; it is **not** a
  non-invasive check and must be explicitly approved.
