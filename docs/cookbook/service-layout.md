# Service layout and account helpers

`lib/service-layout.nix` defines **pure data contracts**. It does not
invent a second option-merging framework and does not wrap `lib.mkIf`,
`lib.mkMerge` or native service modules.

`mkGameDirectories` derives a consistent game-specific directory layout
from a service HOME, while supporting an independent `gameDir` for
`/srv` migrations. It validates name components and absolute paths before
rendering tmpfiles and bind mount sources. It does **not** inspect the
runtime filesystem or claim that a directory has been provisioned.

`mkStaticServiceAccount` is used for identical host/container UID/GID
declarations. NixOS containers have to agree on ownership for writable
bind mounts. **Do not enable private-user remapping without a separate
UID mapping test.**

The API remains available to internal modules via a normal Nix import. Public
`flake.lib.helpers`, host `configuration.nix`, and native NixOS
options stay unchanged.

## Edge cases

- Refuse relative roots, traversal, `/nix/store` and non-component game keys.
- Paths are still subject to symlinks and mount boundaries at runtime:
  validate using `realpath`, `findmnt`, UID/GID, and permissions *before*
  copying data or switching services.
- Two services must not be assigned the same data root without an explicit
  sharing contract.
- Never change a running service's UID or ownership recursively during
  activation.

Run `nix run -L .#framework-test` and the repository's focused host evaluation
workflow. See upstream
[NixOS module system](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
and [systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html).
