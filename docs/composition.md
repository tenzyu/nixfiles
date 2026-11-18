# Named composition: semantic phases, not a replacement for Nix modules

Nix already has three distinct forms of composition:
- Pure value transformation: `lib.pipe`.
- Fixed-point overlay extension: `lib.composeManyExtensions` / `lib.extends`.
- NixOS module definitions: `imports`, `lib.mkMerge` and type/priority merge.

These are not equivalent. In particular, Nix attrset `//` is a **shallow
overwrite**, not NixOS option merging. Avoid a custom abstraction that
pretends they are interchangeable.

`lib/composition.nix` adds a deliberately narrow, general primitive:
`namedPipeline {label; steps;}`. Its value is a first-class object with
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

Concrete callers: NixOS and Home Manager seed materializers each identify
the phases `read-typed`, `compact-optional-fields` and
`emit-native-module`. The result is unchanged and existing typed options,
nixd completion and definition priority are preserved.

### Edge cases and limits

- Nix is lazy: `addErrorContext` covers evaluation of the stage result
  only to weak head normal form. It cannot promise that errors in lazily
  forced nested values later always include the stage name.
- No `deepSeq` on every intermediate result: it can force huge graphs,
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
