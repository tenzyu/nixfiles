# Read-only inspection

## Prerequisites

A checkout with Nix, flakes enabled and access to the pinned flake inputs. Commands run from the repository root. If direnv already loaded the shell, run the commands directly; do not repeatedly wrap them in `nix develop -c`.

## Observe the declared configuration

```sh
git rev-parse HEAD
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json
nix eval --raw .#nixosConfigurations.neko7.config.system.build.toplevel.drvPath
```

Expected: the host list contains `neko5`, `neko6` and `neko7`; the last expression yields a `.drv` store path. Failure can mean missing flake inputs, an evaluation error, or a policy constraint; **no successful output here proves an active generation or a running unit**.

## Validate the source

```sh
python3 scripts/ci/check_docs.py
python3 -m unittest discover -v -s scripts/ci -p 'test_docs.py'
python3 scripts/ci/wiki_scan.py --summary
python3 scripts/ci/retrieval_eval.py --smoke
nix run -L .#framework-test
```

The Python checks inspect files, source metadata and retrieval routes without OS activation. The Nix command builds/runs the focused framework tests and can fetch dependencies. The CI-equivalent Nix matrix is in [PR validation](ci-validation.md); `nix flake check` is deliberately not the fast-path PR gate.

## Stop conditions

Do not interpret `nixos-rebuild test` as an inspection command: it activates a configuration. Do not run `switch`, VM resets, secret bootstrap, GC prune or `home-layout-migrate apply` as part of a documentation or inspection task. Record a failure with its exact revision and command before retrying.
