# Instance operations — admitted container scope

Nix owns releases; Incus owns instances and mutable state. On an explicitly approved and activated neko7, use:

```sh
just
just images
just status
just instances
just lab experiment
just lab-stop experiment
```

The first four commands are read-only. Ephemeral lab containers require a restricted enrolled client; stopping an ephemeral container deletes it, so export required results first. The lab is limited to eight allocated instances, zero VMs, eight aggregate CPUs and 8 GiB memory; default two CPUs and 2 GiB. These are allocation limits, not a guarantee of host headroom or storage quota. The operator default project remains trusted.

Syncthing and Immich image/system outputs are **build-only candidates**. Standalone service tests and image builds are not exact-image lifecycle proof. VM launch, durable creation, backup, update, restore and retirement recipes are deferred pending follow-up evidence. No real-data operation is admitted here. See [compute platform](compute-host.md), [platform operations](compute-platform-operations.md) and [incumbent workload migration](compute-workload-migration.md).
