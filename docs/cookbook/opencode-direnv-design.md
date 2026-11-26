# OpenCode direnv integration design

## Execution path

```text
shell tool: command + workdir
  -> OpenCode Shell.create: session environment or server environment
  -> shell.create.before: direnv status --json, then direnv export json
  -> invocation.env receives the exported delta
  -> child shell executes the original command
```

OpenCode 2.2.1 exposes `cwd` and a mutable `env` in the shell hook. Its implementation constructs a fresh environment for each invocation. The plugin consumes that environment, including any session-specific values, without adding variables from the server's environment. Concurrent repositories therefore do not share exported variables.

Direnv finds the nearest `.envrc` from the invocation's working directory. The plugin requires its status to be `Allowed`. An explicitly denied file also blocks the invocation because direnv's export command treats `Denied` as a successful no-op. JSON `null` values become unset variables. If the environment fails to load, the plugin rejects the shell invocation instead of running the command with missing tools.

## Cache and garbage collection

`nix develop -c` reconstructs the development shell for each command. Nix reuses an unchanged environment already in the store rather than downloading every package on each invocation. Repeated copy messages require another cause, such as a changed store path or garbage collection. A cold run and an immediate repeat on neko7 confirmed downloads on the first run and none on the repeat.

Nix-direnv caches the output of `nix print-dev-env --profile` under `.direnv/`. It registers GC roots for the environment and flake inputs. Subsequent exports load the cached shell environment instead of entering `nix develop` again. The plugin does not cache JSON exports. This preserves direnv's file watching, environment-dependent exports and approval revocation.

Tenzyudotcom's `.envrc` watches `nix/*.nix` in addition to nix-direnv's automatic watches for `.envrc`, `flake.nix`, and `flake.lock`. It disables fallback to a previously working devShell, so a broken flake cannot silently select old tools. It also prohibits automatic lock-file writes.

The first load and a changed devShell can still download packages. Cache logs are captured by the plugin's subprocess rather than appended to every tool result. To inspect an environment failure, run `direnv export json` directly in that repository. Do not publish its JSON: it can contain secrets.

## Limits

- The hook applies to OpenCode shell processes. It does not inject environments into MCP servers, LSP processes, or the OpenCode server itself.
- The plugin selects the environment when it creates the process. A command that changes directories into another repository keeps the initial environment. Set `workdir` on a separate shell invocation or use `direnv exec /other/repository command`.
- Direnv exports environment variables, not Bash aliases or shell functions. Project hooks must export what non-interactive commands need.
- `.envrc` changes require renewed approval. Watches rebuild the Nix environment, but do not independently require approval for each watched file.
- Removing `.direnv/` or explicitly cleaning its GC roots requires a cold rebuild. Keep active direnv roots when using `nh clean`.

## Sources

- [OpenCode V2 shell hook contract](https://opencode.ai/v2/docs/build/plugins/server#shell)
- [OpenCode 2.2.1 shell implementation](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/core/src/shell.ts#L264-L317)
- [OpenCode 2.2.1 session environment](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/core/src/session/environment.ts)
- [Direnv execution and approval model](https://direnv.net/man/direnv.1.html)
- [Direnv 2.37.1 approval states](https://github.com/direnv/direnv/blob/v2.37.1/internal/cmd/rc.go)
- [Nix-direnv 3.1.2 cache, watches, and GC roots](https://github.com/nix-community/nix-direnv/blob/3.1.2/direnvrc)
- [Rejected session-start plugin: global process.env mutation](https://github.com/simonwjackson/opencode-direnv/blob/main/src/index.ts)

See the [repository setup and verification procedure](opencode-devshells.md).
