# Change a host's explicit feature selection

1. **Read the current host selection.** Open `modules/00-hosts/<host>/configuration.nix`. Check whether the system or the named user selects the feature. Preserve the existing typed host and user feature interface.
2. **Trace native effects.** Find the registered implementation under `modules/50-features/`. Check conditional contributions under `modules/60-integrations/`. Check the locked nixpkgs/Home Manager option before adding helper code.
3. **Change the file responsible for the setting.** Host files select features. Feature files implement settings. Integrations define cross-feature rules. No global `allowUnfree` shortcut, opaque bundles or competing module merge DSL.
4. **Check before requesting activation.** Use the [inspection commands](inspect.md), the affected framework tests and the [native CI checks](ci-validation.md). Compare the evaluated native options and `.drv` changes. Record failing and skipped gates separately.
5. **Request approval for operational effects.** Explicitly identify restarts, data movement, credentials, public access and rollback preconditions. Obtain approval before you run `nixos-rebuild test` or `nixos-rebuild switch`. A generation rollback does not restore mutable data.

The precise projection semantics are in [Architecture](../memory/architecture.md); permanent non-goals and acceptance constraints in [Decisions](../memory/decisions.md).
