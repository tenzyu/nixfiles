# Instance operations

One source of truth per operation: **Nix describes a software release, Incus owns the instance and its mutable state.** Adding or removing an instance does not change the host generation. Use the existing authenticated SSH session on neko7 and the nixfiles checkout. The native `just` task runner is a command menu, not a daemon, reconciler, registry, or backend API. It is installed with Incus.

## Normal workflow

Read-only discovery: `just`, `just images`, `just instances`. The image list is derived from the actual flake outputs, not a catalog.

```sh
# Operator-approved new persistent instance; choose disk, CPU, RAM explicitly.
just new syncthing sync 40GiB
just new immich photos 100GiB 4 6GiB
# Run the native manager for inspection and start/stop.
sudo incus info local:photos --project default
sudo incus exec local:photos --project default -- journalctl -u immich-server -n 80
sudo incus stop local:photos --project default
sudo incus start local:photos --project default
# Backup leaves the machine stopped. Use an approved private directory (0700), preferably off-host.
just backup photos /approved/backup/photos.tar.gz
# Only after backup/restore and service-specific schema acceptance.
just update photos /approved/backup/photos-before-update.tar.gz
# After stopping and isolated restore verification, type the exact instance name.
just delete photos /approved/backup/photos.tar.gz
```

New instances carry a native Incus `user.nixfiles.workload` annotation solely for resolving the release output, not a duplicate database. They autostart and are deletion-protected. The creation recipe builds before importing, keeps a temporary native Nix GC root until the operation finishes, uses a release-specific image alias, and never edits the host, existing VM or firewall. A duplicate instance name fails; inspect any incomplete instance with native Incus before retrying. The operator can still use native commands. Serialize operations on the same instance; no parallel manual mutation while a recipe is running. For multiple instances of a workload, enroll each guest under a unique Tailnet node identity/name. Delete only accepts a stopped managed instance and explicit existing backup path; the receipt's hash is printed, not proof of recoverability. An isolated restore is operator-verified and explicitly confirmed. Incus deletes the instance disk and its instance-owned snapshots, not independent storage volumes. No force or silent prune. Image aliases/old backups are not automatically deleted.

`just update` builds independently, creates an offline whole-instance export at a new path, and applies the reviewed guest closure after typed approval. It does not prove application-level consistency or safe database downgrades. Confirm an existing verified restorable backup before the operation, and verify application health afterward. Failure leaves the backup and the native generations; never blindly retry or automatically roll back mutable data. For major database migrations, follow the workload's upstream backup/restore procedure first. The helper uses existing Incus authority and never grants that authority to an agent.

Agents use the restricted `lab:` remote directly, or `just lab NAME`, `just lab-vm NAME`, `incus exec lab:NAME -- COMMAND`, `just lab-stop NAME`. No sudo; stop deletes ephemeral instances, so retrieve evidence first. For an arbitrary preview use existing SSH local forwarding; shared Caddy routes still require operator approval. See [platform operations](compute-platform-operations.md).

## Add another persistent workload

Add exactly one public file in `modules/40-workloads/`, following `syncthing.nix` or `immich.nix`. It contains ordinary native NixOS service options and exports `neko7-NAME-image`, `neko7-NAME-system` via the upstream Incus image helper, plus a matching `checks.personal-workload-NAME` machine test. Use a workload-specific native test when appropriate. The native `pkgs.testers.runNixOSTest` is defined in the same workload file, so a new workload has no central test dispatch table. CI discovers image names from the flake outputs and builds/tests each one; no host feature, central service catalog, CI matrix or per-project agent adapter needs a new entry. Use the pinned stable nixpkgs unless an isolated guest explicitly requires another reviewed pin. Do not allow insecure packages. Image software removal is independent from instance/data removal; existing instances remain Incus-owned until explicit retirement. Do not remove their release declarations before arranging future maintenance or a verified retirement.

Native nspawn and user-service incumbents retain their reviewed release and recovery contracts in [existing workload migration](compute-workload-migration.md). No forced conversion of those services, no automatic changes to live state. Infrastructure and placement remain in `00-hosts`, reusable capabilities in `50-features`, product integration in `60-integrations`, independent workloads in `40-workloads`. Do not route per-app runtime facts through host evaluation. Future identity providers, tunnels and agent frontends fit as separate native capabilities, without changing the instance lifecycle.
