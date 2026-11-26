---
type: Playbook
title: "opencode-devshells.md"
description: "Direnv integration for OpenCode shell invocations"
status: stable
source_revision: 22191670806242933bc156e4a5e0cd9ad3ea14f1
sources:
  - id: source-1
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/assets/opencode/direnv.ts
    title: "assets/opencode/direnv.ts"
  - id: source-2
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/modules/50-features/opencode-direnv.nix
    title: "modules/50-features/opencode-direnv.nix"
---

# Enable per-command development environments in OpenCode

The `opencode-direnv` Home Manager feature loads an approved direnv environment into each OpenCode shell invocation. It does not start the shared server inside a project's devShell or change `process.env`.

## Execution path

See the [OpenCode direnv execution path](opencode-direnv-design.md#execution-path).

## Cache and garbage collection

See the [cache and garbage collection behavior](opencode-direnv-design.md#cache-and-garbage-collection).

## Enable a repository

If the flake defines `devShells.<system>.default`, create `.envrc`:

```sh
nix_direnv_disallow_fallback
watch_file nix/*.nix
use flake . --no-write-lock-file
```

Omit the `watch_file` line if the project has no `nix/` directory. Add watches for any other files that determine the devShell. Add `.direnv/` to `.gitignore`. Track `.envrc` in Git.

Review `.envrc` before running `direnv allow` in its directory. Do not configure blanket approval for the home directory or automatically approve files from plugins. Approval permits `.envrc` to execute as your user. `use flake` permits the repository's shell hook to execute.

After Home Manager activation, OpenCode discovers `~/.config/opencode/plugins/direnv.ts` globally. Config reload does not require a server restart. Check `/api/plugin` for `nixfiles.direnv` at the target location.

Run commands normally with the shell tool's `workdir` set to the repository or a subdirectory. This also works for other repositories with approved `.envrc` files. Select named shells explicitly. Use `nix develop .#browser-verification -c ...` when a task needs a different shell from the repository's default.

## Limits

Read the [direnv integration limits](opencode-direnv-design.md#limits).

## Verify

```sh
nix build .#checks.x86_64-linux.opencode-direnv
nix build .#checks.x86_64-linux.home-migration
nix build .#checks.x86_64-linux.rtk-rewrites
```

The direnv tests use real subprocesses and isolated temporary homes. They cover concurrent repositories, unset values, subdirectories, edited scripts, denied scripts, and failed scripts. To verify the actual child environment, test the installed plugin through OpenCode's shell API.

RTK is enabled separately. Its 1.2.0 rewrite registry maps `biome` to the ESLint-only `rtk lint` command. The `rtk` feature excludes Biome invocation forms and project lint scripts from rewriting. Its check proves that these commands remain native while `git status` still uses RTK. See [the upstream correctness report](https://github.com/rtk-ai/rtk/issues/3117).

To disable the integration, set `local.users.tenzyu.features.opencode-direnv.enable = false` and switch the NixOS configuration. Project `.envrc` files and nix-direnv caches remain on disk.

## Sources

See the [integration source references](opencode-direnv-design.md#sources).

## Wiki context

The host enables this integration as a configuration declaration. The per-command hook does not activate the candidate managed OpenCode server. See [host state](../memory/host-state.md).
