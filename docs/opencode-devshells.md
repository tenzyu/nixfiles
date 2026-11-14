# Per-command development environments in OpenCode

The `opencode-direnv` Home Manager feature loads an approved direnv environment into each OpenCode shell invocation. It does not start the shared server inside a project's devShell or change `process.env`.

## Execution path

```text
shell tool: command + workdir
  -> OpenCode Shell.create: session environment or server environment
  -> shell.create.before: direnv status --json, then direnv export json
  -> invocation.env receives the exported delta
  -> child shell executes the original command
```

OpenCode 2.2.1 exposes `cwd` and a mutable `env` in the shell hook. Its implementation constructs a fresh environment for each invocation. The plugin consumes that environment, including any session-specific values, without adding variables from the server's environment. Concurrent repositories therefore do not share exported variables.

Direnv finds the nearest `.envrc` from the invocation's working directory. The plugin requires its status to be `Allowed`. An explicitly denied file also blocks the invocation because direnv's export command treats `Denied` as a successful no-op. JSON `null` values become unset variables. Failed environment loads reject the shell invocation rather than running the command with missing tools.

## Cache and garbage collection

`nix develop -c` reconstructs the development shell for each command. Nix does not download every package on every invocation: an unchanged environment already in the store is reused. Repeated copy messages require another cause, such as a changed store path or garbage collection. A cold run and an immediate repeat on neko7 confirmed downloads on the first run and none on the repeat.

Nix-direnv caches the output of `nix print-dev-env --profile` under `.direnv/`. It registers GC roots for the environment and flake inputs. Subsequent exports load the cached shell environment instead of entering `nix develop` again. The plugin deliberately does not cache JSON exports, so it preserves direnv's file watching, environment-dependent exports, and approval revocation.

Tenzyudotcom's `.envrc` watches `nix/*.nix` in addition to nix-direnv's automatic watches for `.envrc`, `flake.nix`, and `flake.lock`. It disables fallback to a previously working devShell, so a broken flake cannot silently select old tools. It also prohibits automatic lock-file writes.

The first load and a changed devShell can still download packages. Cache logs are captured by the plugin's subprocess rather than appended to every tool result. To inspect an environment failure, run `direnv export json` directly in that repository. Do not publish its JSON: it can contain secrets.

## Enable a repository

For an existing flake with `devShells.<system>.default`, create `.envrc`:

```sh
nix_direnv_disallow_fallback
watch_file nix/*.nix
use flake . --no-write-lock-file
```

Omit the `watch_file` line if the project has no `nix/` directory. Add watches for any other files that determine the devShell. Ignore `.direnv/` in Git, but keep `.envrc` under version control.

Review `.envrc` before running `direnv allow` in its directory. Do not configure blanket approval for the home directory or automatically approve files from plugins. Approval allows the script to execute as your user, and `use flake` trusts the repository's shell hook.

After Home Manager activation, OpenCode discovers `~/.config/opencode/plugins/direnv.ts` globally. Config reload does not require a server restart. Check `/api/plugin` for `nixfiles.direnv` at the target location.

Run commands normally with the shell tool's `workdir` set to the repository or a subdirectory. This also works for other repositories with approved `.envrc` files. Named shells remain explicit: use `nix develop .#browser-verification -c ...` when a task needs a different shell from the repository's default.

## Limits

- The hook applies to OpenCode shell processes. It does not inject environments into MCP servers, LSP processes, or the OpenCode server itself.
- The environment is selected at process creation. A command that changes directories into another repository keeps the initial environment. Set `workdir` on a separate shell invocation or use `direnv exec /other/repository command`.
- Direnv exports environment variables, not Bash aliases or shell functions. Project hooks must export what non-interactive commands need.
- `.envrc` changes require renewed approval. Watches rebuild the Nix environment, but do not independently require approval for each watched file.
- Removing `.direnv/` or explicitly cleaning its GC roots requires a cold rebuild. Keep active direnv roots when using `nh clean`.

## Verify

```sh
nix build .#checks.x86_64-linux.opencode-direnv
nix build .#checks.x86_64-linux.home-migration
nix build .#checks.x86_64-linux.rtk-rewrites
```

The direnv tests use real subprocesses and isolated temporary homes. They cover concurrent repositories, unset values, subdirectories, edited scripts, denied scripts, and failed scripts. The installed plugin must also be checked through OpenCode's shell API to verify the actual child environment.

RTK is enabled separately. Its 1.2.0 rewrite registry maps `biome` to the ESLint-only `rtk lint` command. The `rtk` feature excludes Biome invocation forms and project lint scripts from rewriting. Its check proves that these commands remain native while `git status` still uses RTK. See [the upstream correctness report](https://github.com/rtk-ai/rtk/issues/3117).

To disable the integration, set `local.users.tenzyu.features.opencode-direnv.enable = false` and switch the NixOS configuration. Project `.envrc` files and nix-direnv caches remain on disk.

## Sources

- [OpenCode V2 shell hook contract](https://opencode.ai/v2/docs/build/plugins/server#shell)
- [OpenCode 2.2.1 shell implementation](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/core/src/shell.ts#L264-L317)
- [OpenCode 2.2.1 session environment](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/core/src/session/environment.ts)
- [Direnv execution and approval model](https://direnv.net/man/direnv.1.html)
- [Direnv 2.37.1 approval states](https://github.com/direnv/direnv/blob/v2.37.1/internal/cmd/rc.go)
- [Nix-direnv 3.1.2 cache, watches, and GC roots](https://github.com/nix-community/nix-direnv/blob/3.1.2/direnvrc)
- [Rejected session-start plugin: global process.env mutation](https://github.com/simonwjackson/opencode-direnv/blob/main/src/index.ts)
