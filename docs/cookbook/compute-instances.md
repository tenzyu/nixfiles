# Instance operations

Nix owns releases; Incus owns instances and mutable state. Run the menu from the nixfiles checkout on neko7. `just status` reads native inventories; it is not an application-health registry.

```sh
just
just images
just status
just new syncthing sync 40GiB
just new immich photos 100GiB 4 6GiB
sudo incus info local:photos --project default
sudo incus stop local:photos --project default
sudo incus start local:photos --project default
# Existing private parent directory (0700), preferably off-host.
just backup photos /approved/backup/photos-20261125
# Maintenance window, verified prior restore and schema review required.
just update photos /approved/backup/photos-before-update
```

New VMs have a native workload annotation, auto-start and deletion protection. The release stays GC-rooted during creation/update. `new` and `update` require guest `/etc/neko7/readiness` to succeed; update additionally checks the active and system profile closures. This is service readiness, not schema rollback or full application acceptance.

Each compound operation holds a nonblocking advisory instance lock under /run/lock/neko7-instances. Native direct Incus commands bypass this lock; the operator must serialize those with recipes. Backup makes a new private directory atomically, stops the target and writes instance.tar.gz, identity.json (name, native volatile.uuid, project, workload), SHA256SUMS only after export succeeds. A partial directory is not a valid backup. Backup leaves the VM stopped. A successful checksum is not a successful restore. Verify the archive off-host and protect it as credentials.

## Recovery

If an operation fails, do not blindly retry. Inspect `incus info local:NAME --project default`, `incus config get local:NAME volatile.uuid --project default`, the bundle and guest `readlink -e /run/current-system /nix/var/nix/profiles/system`. The old and candidate closures are printed before update; the native generations remain available subject to GC. A failed export leaves the instance stopped or in its observed native state; inspect before restarting. A failed closure import has not changed the profile unless that subsequent step ran. If activation fails after profile mutation, do not assume running and boot generations agree. Preserve the backup, compare actual generations and application schema; use native generation rollback only if the application permits it, otherwise recover into an isolated restored instance. Never automatically overwrite mutable data. Manual recovery requires explicit approval.

## Retirement (no automatic delete)

Permanent deletion is intentionally not a menu recipe. Stop the instance; record its native UUID, verify the bundle identity and stored SHA256SUMS, confirm no writes/restart since the backup or explicitly accept the data-loss window, and review expanded devices, independent volumes, snapshots and external data. Restore the export into a separate disposable, non-networked instance and verify application data before any destructive action. Incus 7.6 import syntax is `incus import local: ARCHIVE RESTORE_NAME --project default -c boot.autostart=false`; inspect and disable inherited NICs (for a default-profile eth0, `incus config device add local:RESTORE_NAME eth0 none --project default`) and verify the expanded devices contain no NIC before first boot. Use a dedicated isolated recovery environment for nonstandard devices/volumes; never assume the default-profile example applies to an arbitrary backup. The restored identity must never join the Tailnet while the original exists. Confirm an independent backup location. If the owner separately approves permanent removal, use the native Incus UI/CLI with the exact verified target. Incus requires explicit removal of deletion protection. If interrupted after unprotecting, immediately re-enable protection on the surviving instance and re-evaluate the retirement gate; do not retry deletion blindly. The recipe never unprotects or deletes persistent instances. A missing release definition does not retire a live instance.

## Add a workload

One file in `modules/40-workloads/`: native service module, guest readiness command, image/system outputs, service-module test and exact-image lifecycle check. CI derives the matrix from image outputs. No central catalog, host declaration or CI list edit. A specialized workload can need additional storage, driver or security capabilities. Tests use disposable data; the application owner still validates real migration and recovery. Use the existing stable or reviewed isolated unstable pin without insecure allowlists.

Agents use restricted `lab:` credentials and `just lab NAME` / `just lab-vm NAME` / `just lab-stop NAME`. Stop deletes ephemeral instances. Lab project admission limits are initial 8 allocated instances, at most 3 VMs, aggregate 8 CPUs / 8 GiB configured memory, default 2 CPUs / 2 GiB. These are configured resource limits, not a guarantee of physical headroom; QEMU overhead, images, snapshots, storage and host-native tasks are outside the memory/CPU budget. On dir/ext4, filesystem quotas depend on project quota support; VM virtual disk size bounds guest block capacity, not aggregate host space. Do not assert disk exhaustion containment until verified. No new storage migration.

For previews, use SSH forwarding by default, Caddy only for supervised operator-approved sharing. [Platform operations](compute-platform-operations.md). Existing Minecraft and user-service releases follow [existing workload migration](compute-workload-migration.md).
