# Native operator interface

To open the operator menu or run a recipe, use these commands in the nixfiles checkout:

~~~sh
nix run .#operator
nix run .#operator -- --list
nix run .#operator -- features
nix run .#operator -- store-summary
~~~

The operator uses upstream `just` to run recipes and `fzf` to select entries. The menu is not a
daemon, state database, service orchestrator or second configuration system.
The existing nixpkgs input pins both tools. The operator needs no new input or runtime language. Direct native commands remain available.

## Feature navigation

Select any evaluated system or Home Manager feature across configured hosts,
users and standalone configurations. Rows show effective state, not live
activation. To read the evaluated feature data as JSON, run:

~~~sh
nix eval --json .#operator.features
nix eval --json .#operator.origins.nixos.neko5.system.jay
nix eval --json .#operator.origins.nixos.neko5.home.tenzyu.jay
~~~

The selection menu distinguishes:

- **Selection:** actual files defining a concrete host/user seed (including
  direct embedded Home Manager feature overrides).
- **Registration:** actual files registering the feature, including conditional
  integrations; a registration is not proof that its effects are active.
- **Effective:** repository-owned files from native surviving option
  definitions. Synthetic/default and upstream locations are reported but are
  not opened as editable files.

The evaluator forces only the native definition locations for the selected scope. Embedded Home Manager
metadata is read through an evaluation-only module extension, not a change to
the deployed configuration. File-level source locations are native module
metadata; rg offers line candidates in those files, not a fabricated exact
AST location. If no matching line exists, the editor opens the actual file
at line 1. Cancel safely at any selector. The selector uses the vi-compatible editor from `NIXFILES_EDITOR`, `VISUAL`, or `EDITOR`, or falls back to `nvim`. It runs a single executable without shell evaluation.
The feature browser never edits store or external paths. Use nix-inspect for full
native value exploration and nixd for language-server navigation.

## Nix store

Store summary, native roots, and dead-path browsing are read-only.
The store-clean recipe shows the native dead-path snapshot, requires a local
terminal and exact GC confirmation, verifies current/booted/profile
agreement before and after the preview, and calls only local-daemon native
GC through sudo. It never retires generations, removes GC roots, or invents
a reclaimed-space estimate. Nix rechecks actual liveness. Opening the menu or running CI does not perform GC. See [store maintenance](nix-store-clean.md).

## Other native ports

| Recipe | Delegated operation |
| --- | --- |
| inspect | nix-inspect from the pinned nixpkgs |
| generations | nix-env native generation inventory |
| generation-diff | nvd closure comparison |
| closure-why | native requisites + fzf + nix why-depends |
| failed-services / failed-user-services / journal | systemctl / journalctl |
| images / instances | existing root justfile compute recipes |

No new remote execution, restart, activation, or deployment command is
introduced. Incus inventory retains the existing explicit privilege boundary.

## Design boundaries

Feature inventory and source identity are the Nixfiles supporting subdomain
(lib/operator/feature-inventory.nix); GC admission is the local operator
policy (lib/operator/store-policy.sh). UI adapters under tools/operator
compose native commands without duplicating their algorithms. There is no
compatibility wrapper for the retired Framework CLI. Add a recipe instead
of a new parser when a native command already covers a use case. Prefer a
packaged upstream UI when it satisfies the same safety contract.
NH's ordinary cleanup also manages generations/roots; this interface
does not delegate generation deletion to it.

Validation:
~~~sh
nix build -L --no-link .#checks.x86_64-linux.operator-interface
~~~
The check evaluates real feature source metadata and both NixOS/HM scopes,
builds the shell entry points, verifies just recipes and tests GC admission
without performing GC. Interactive editor/TUI and actual daemon behavior
remain operator acceptance, not implied by a successful derivation.
