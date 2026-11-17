# T3 Code and Codex on neko7

## Ownership and scope

The neko7 Home Manager feature `t3code-neko7` enables a dedicated
`t3code-neko7.service` user unit (loopback 127.0.0.1:3773) and installs the
T3 CLI. The existing `codex` feature installs the Codex CLI from the
`llm-agents.nix` revision pinned by `flake.lock`. T3 comes from the
`nixpkgs-unstable` input pinned by the same lockfile. No Flake inputs are
updated.

This is a *new* server with its own T3 state, not a migration of existing
OpenCode sessions. Do not run T3's own `t3 service install` for this server:
the declarative unit already owns it. The old OpenCode service and
`opencode-direnv` feature are not modified.

## Preconditions — before activating

- Review the PR and check that port 3773 is free:
  `ss -lntp | grep ':3773' || true`
- Confirm Codex and T3 are available from the pinned lock:
  `nix eval --raw .#nixosConfigurations.neko7.pkgs.unstable.t3code.version`
- Inspect pending NixOS changes with `nh os build` (or
  `nix build .#nixosConfigurations.neko7.config.system.build.toplevel`).
- **Do not automatically switch or reboot.** The user must approve OS
  activation separately. If there is a build error, keep the existing system.

## After explicitly approved activation on neko7

```sh
systemctl --user status t3code-neko7.service
journalctl --user -u t3code-neko7.service -n 60 --no-pager
ss -lntp | grep ':3773'
curl --fail --silent --show-error http://127.0.0.1:3773/ >/dev/null
command -v codex
codex --version
```

A valid `codex --version` only verifies the binary. To authenticate, use
`codex login` as the normal `tenzyu` user (never root); T3 can use the
existing CLI login via **Settings → Providers → Codex → Configure manually**.
For headless login, use the login method supported by the installed Codex CLI.
Do not copy credentials into Nix sources or journal logs.

## Remote access

The server intentionally listens on **loopback only**. Do not expose port
3773 on LAN, Tailscale, or the public interface without an independently
reviewed access design. Use a Tailscale Serve HTTPS route only after inspecting
existing Serve routes, tailnet ACLs, the intended hostname and certificate
configuration. Alternatively use an authenticated SSH tunnel to
127.0.0.1:3773. T3's pairing and provider approvals are separate from
Tailscale access controls.

Never enable `--lan`, Tailscale Funnel or unrestricted `Full access` merely
to make the UI reachable. Pairing and any T3 Connect enablement are separate,
user-approved steps. Existing OpenCode remote access remains unchanged.

## Verify the intended workflow

1. T3 Web UI loads, and the Codex provider is detected and authenticated.
2. Start a harmless disposable project. Confirm permission prompts and a
   normal command before granting broader privileges.
3. Create a Git worktree and verify the correct default `direnv` devShell.
   T3 does not implicitly export a repository's `.envrc` into arbitrary
   provider processes; check the actual agent shell and Git hooks. Do not
   substitute repeated `nix develop -c` invocations as a workaround.
4. Test a local commit and PR creation on a disposable branch after the user
   grants the appropriate repository permissions.
5. Disconnect/reconnect a remote client and verify session continuity.
6. Check that OpenCode Web and its pre-existing sessions still work.

If a Codex sign-in or provider probe fails, inspect the local provider status
before modifying authentication state. If `Codex app-server` probes time out
despite valid credentials, official T3 documentation describes
`T3CODE_CODEX_PROBE_TIMEOUT_MS=60000` as a targeted diagnostic setting.

## Rollback

Disable the new feature and `codex.enable` in
`modules/00-hosts/neko7/configuration.nix`, then rebuild and activate the
prior configuration with approval. Alternatively stop only this unit
temporarily:

```sh
systemctl --user stop t3code-neko7.service
```

Stop/disable the new unit before configuring any different T3 service on the
same port or state directory. Do not delete `~/.t3` or Codex credentials;
their state is not owned by NixOS and may be needed for recovery.

## Evidence and limits

- [T3 remote access](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
- [T3 background service](https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md)
- [T3 Codex provider](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-codex.md)
- [nixpkgs T3 wrapper](https://github.com/NixOS/nixpkgs/blob/nixpkgs-unstable/pkgs/by-name/t3/t3code/package.nix)
- [Existing OpenCode/direnv](opencode-devshells.md)

GitHub-side changes do **not** imply that neko7 has fetched or activated them.
Running processes, network access, Codex sign-in and full Nix evaluation require
verification on neko7; no SSH execution was available during PR preparation.
