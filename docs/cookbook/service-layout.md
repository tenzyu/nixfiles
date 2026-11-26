# Service layout and account helpers

`lib/service-layout.nix` defines pure Nix data contracts. It does not
invent a second option-merging framework and does not wrap `lib.mkIf`,
`lib.mkMerge` or native service modules.

`mkGameDirectories` derives the game directory layout from a service HOME.
It accepts an independent `gameDir` for `/srv` migrations. It validates name components and absolute paths before
rendering tmpfiles and bind mount sources. It does **not** inspect the
runtime filesystem or claim that a directory has been provisioned.

Use `mkStaticServiceAccount` to declare identical host and container UID/GID values. NixOS containers have to agree on ownership for writable
bind mounts. **Do not enable private-user remapping without a separate
UID mapping test.**

Internal modules access the API through a normal Nix import. Public
`flake.lib.helpers`, host `configuration.nix`, and native NixOS
options stay unchanged.

## Edge cases

- The helpers reject relative roots, traversal, `/nix/store`, and game keys that are not single path components.
- Symlinks and mount boundaries affect paths at runtime.
  Validate using `realpath`, `findmnt`, UID/GID, and permissions *before*
  copying data or switching services.
- Two services must not share a data root unless an explicit agreement defines how they share it.
- Never change a running service's UID or ownership recursively during
  activation.

Run `nix build -L --no-link .#checks.x86_64-linux.framework` and the repository's focused host evaluation
workflow. See upstream
[NixOS module system](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
and [systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html).
