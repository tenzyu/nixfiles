---
type: Reference
title: Named Nix composition
description: Value composition compared with NixOS module merge semantics.
status: stable
sources:
  - id: composition
    resource: ../../lib/composition.nix
    title: Named composition implementation
---

# Named composition of ordinary Nix values

Nix already has three distinct forms of composition:
- Pure value transformation: `lib.pipe`.
- Fixed-point overlay extension: `lib.composeManyExtensions` / `lib.extends`.
- NixOS module definitions: `imports`, `lib.mkMerge` and type/priority merge.

These are not equivalent. In particular, Nix attrset `//` is a **shallow
overwrite**, not NixOS option merging. Avoid a custom abstraction that
pretends they are interchangeable.

`lib/composition.nix` defines `namedPipeline {label; steps;}` for ordinary Nix values. Its value is a first-class object with
`stageNames` and `run`. Each stage has a distinct, nonempty `name`
and a `run` function. Composition delegates directly to `lib.pipe`
and attaches stage-specific `builtins.addErrorContext`.

Example:

```nix
let
  composition = import ./lib/composition.nix {inherit lib;};
  projection = composition.namedPipeline {
    label = "example-projection";
    steps = [
      {name = "read-typed"; run = x: x.module;}
      {name = "drop-null"; run = lib.filterAttrs (_: x: x != null);}
      {name = "emit-target"; run = x: {config = x;};}
    ];
  };
in projection.run source
```

The NixOS and Home Manager seed materializers each identify
the phases `read-typed`, `compact-optional-fields` and
`emit-native-module`. The result is unchanged and existing typed options,
nixd completion and definition priority are preserved.

### Edge cases and limits

- Nix uses lazy evaluation. `addErrorContext` covers evaluation of the stage result
  only to weak head normal form. It cannot promise that errors in lazily
  forced nested values later always include the stage name.
- Do not apply `deepSeq` to every intermediate result. It can force large graphs,
  alter performance and reveal recursive evaluation cycles.
- The helper does **not** deep-merge attrsets, change option priorities,
  wrap `mkIf`, implement a new type system, or reorder overlay definitions.
- Duplicate names and malformed stages fail rather than being overwritten.
- `flake.lib.helpers.composition` exposes the helper without replacing
  `pkgs.lib` or the native module system.

Tests cover stage order, identity, invalid stages and Nix module wrapper
preservation. Existing `framework-seed` and all-host evaluations cover
the real projection contract.

Sources: [Nixpkgs lib](https://nixos.org/manual/nixpkgs/stable/),
[Nix builtins](https://nix.dev/manual/nix/2.35/language/builtins.html),
[NixOS modules](https://nixos.org/manual/nixos/stable/).

## Named disjoint layers and deliberate replacement

The existing `lib.unionOfDisjoint` fails on overlapping *accessed* keys,
but does not record which source supplied each key. `namedDisjoint` checks key ownership and records the source layer.
It fails on overlapping keys when evaluation demands the merged attrset,
without forcing the layer's values.

```nix
let
  result = composition.namedDisjoint {
    label = "home-context";
    layers = [
      {name = "shared"; attrs = {flakePath = "/repo";};}
      {name = "home"; attrs = {homeStateVersion = "26.05";};}
    ];
  };
in {
  values = result.merged;
  provenance = result.owners; # {flakePath = "shared"; homeStateVersion = "home";}
}
```

`overrideExisting {label; base; replacements;}` is an explicitly named,
shallow replacement. Unlike `lib.overrideExisting`, it **rejects keys
absent from the original attrset** instead of silently ignoring them. It
is intended for schema-shape adjustments in ordinary Nix data, such as
changing existing required seed options to nullable ones.

Neither helper operates on native NixOS option-definition wrappers such as
`lib.mkIf` or `lib.mkMerge`; those always belong in `lib.evalModules`.
`namedDisjoint` validates top-level keys only, never recursively merges
paths, and does not force nested attribute values. Use native
`lib.mergeAttrsList` for thousands of known-compatible layers where
its optimized large-input complexity is more appropriate.
