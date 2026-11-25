# Validation

Nix owns the test dependency graph. The same `checks.x86_64-linux` derivations are built by local operators and GitHub Actions. There is no path-to-test selector or secondary test CLI.

| Evidence | Native command |
| --- | --- |
| Typed adapter and pure Nix functions | `nix build -L --no-link .#checks.x86_64-linux.framework` |
| Host evaluation, trust, desktop policy | `nix build -L --no-link .#checks.x86_64-linux.host-policy` |
| Built desktop packages, clipboard, T3 Serve | `nix build -L --no-link .#checks.x86_64-linux.desktop-packages .#checks.x86_64-linux.clipboard .#checks.x86_64-linux.t3-serve` |
| Local Markdown links | `nix build -L --no-link .#checks.x86_64-linux.docs` |
| Ordinary PR gate (all focused checks, including custom runtime safety tests) | `nix build -L --no-link .#checks.x86_64-linux.validation` |
| Home migration recovery (disposable machine) | `nix build -L --no-link .#checks.x86_64-linux.home-migration` |
| Compute integration | See [compute host](compute-host.md) and `checks.x86_64-linux` |

Nix derivation dependencies and substitution replace hand-maintained source diff dispatch; ordinary checks may take longer on a cold runner. Never interpret a substituted test result as a fresh hardware measurement. NixOS machine tests use the native `runNixOSTest` framework. Use `nix flake check` on a compatible test host when all declared checks (including expensive VM tests) are intended. Evaluation is not a system build, boot or activation.

On-demand GitHub Actions `cache_strict=true` runs the signed SplitCast cache copy audit; it verifies the pinned outputs and closure in an isolated store, not the live neko7 daemon. The source-owned substituter and signing key are scoped to the enabled consumer role. No external cache availability probe is an ordinary PR gate.

Historical selector, migration comparison and retrieval tests are in the [archive](../archive/README.md). Do not add tests of a deleted compatibility interface. Add tests for local behavioral or privilege contracts that native upstream tests do not establish.
