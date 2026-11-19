# Change a host without hiding its choices

1. **Read the current host selection.** Start at `modules/00-hosts/<host>/configuration.nix`. Verify whether the system or the named user selects the capability. Preserve the existing typed host and user feature interface.
2. **Trace native effects.** Find the registered implementation under `modules/50-features/`, then check any conditional `modules/60-integrations/` contribution. Check the locked nixpkgs/Home Manager option before adding helper code.
3. **Change the smallest responsible owner.** Host files select concrete features; feature files implement settings; cross-feature rules belong in integrations. No global `allowUnfree` shortcut, opaque bundles or competing module merge DSL.
4. **Check before requesting activation.** Use the [inspection commands](inspect.md), the affected framework tests and the [CI selection rules](ci-validation.md). Compare the evaluated native options and `.drv` changes. Record failing and skipped gates separately.
5. **Request approval for operational effects.** Explicitly identify restarts, data movement, credentials, public access and rollback preconditions. No `nixos-rebuild test` or `switch` without approval; rollback of the generation does not roll back mutable data.

The precise projection semantics are in [Architecture](../memory/architecture.md); permanent non-goals and acceptance constraints in [Decisions](../memory/decisions.md).
