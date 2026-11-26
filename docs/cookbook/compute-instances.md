# Instance operations for admitted containers

Nix manages releases. Incus manages instances and mutable state. After the operator approves and activates the neko7 configuration, run these commands:

```sh
just
just images
just status
just instances
just lab experiment
just lab-stop experiment
```

The first four commands are read-only. To use ephemeral `lab` containers, enroll a restricted client. Export required results before stopping a container. Incus deletes ephemeral containers when they stop. The lab permits eight allocated instances, zero VMs, eight aggregate CPUs and 8 GiB of memory. The defaults are two CPUs and 2 GiB of memory. These limits restrict allocation. They do not guarantee available host resources or impose a storage quota. The operator default project remains trusted.

Syncthing and Immich image/system outputs are **build-only candidates**. Standalone service tests and image builds are not exact-image lifecycle proof. VM launch, persistent creation, backup, update, restore, and retirement procedures require further evidence. No real-data operation is admitted here. See [compute platform](compute-host.md), [platform operations](compute-platform-operations.md) and [incumbent workload migration](compute-workload-migration.md).
