---
type: Runbook
title: Development and recovery on neko7
status: stable
source_revision: 191b6cb7daa9f98de76115c9d0efe0a159eefd23
sources:
  - {id: host, resource: "../modules/00-hosts/neko7/configuration.nix"}
  - {id: serve, resource: "../modules/50-features/networking/t3code-tailnet.nix"}
  - {id: acceptance, resource: "https://github.com/tenzyu/splitcast/pull/12"}
---

# Run and recover T3 Code and Codex on neko7

## Ownership and scope

For the independent runtime deployment and first cutover, follow the [workload migration procedure](compute-workload-migration.md). The earlier observations below are historical, not proof of profile activation.

The neko7 Home Manager feature `t3code-neko7` enables a dedicated
`t3code-neko7.service` user unit (loopback 127.0.0.1:3773) and exposes the T3 CLI through its independent native Nix runtime profile. The existing `codex` feature installs the Codex CLI from the
`llm-agents.nix` revision pinned by `flake.lock`. T3 comes from the
`nixpkgs-unstable` input pinned by the same lockfile. The configuration does not update flake inputs.

This is a *new* server with its own T3 state, not a migration of existing
OpenCode sessions. Do not run T3's own `t3 service install` for this server.
The declarative unit already manages it. The old OpenCode service and
`opencode-direnv` feature are not modified.

## Preconditions for activation

- If you install T3 for the first time, check that port 3773 is free. Otherwise, identify the process that owns the port:
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
existing CLI login via Settings, then Providers, Codex and Configure manually.
For headless login, use the login method supported by the installed Codex CLI.
Do not copy credentials into Nix sources or journal logs.

## Remote access

The Home Manager service binds to `127.0.0.1:3773`. The neko7 system feature
`t3code-tailnet` declares the existing tailnet-only HTTPS route on port 8445.
Tailscale persists node routes. The NixOS oneshot has no boot target. Restoring
one missing route uses the native CLI and preserves the other Serve ports.
T3 client pairing and provider approvals remain separate.

See [why the T3 route uses the Tailscale node CLI](t3code-serve-design.md).

To check the route without changing it, run `tailscale serve status --json` locally. Compare port 8445 with the feature declaration. Keep the raw inventory private. From the intended
tailnet client, GET the node's HTTPS root on 8445 with TLS verification enabled.

If a restore is needed after approved activation, confirm the intended client
ACLs, certificate, target and other route owners. Save a private copy of the Serve configuration before you change it. With a single writer during the restore window, use
`sudo systemctl start t3code-tailnet.service` **only with route-change approval**.
Matching state exits successfully. A conflicting or Funnel-enabled endpoint
fails for inspection. Review the before/after snapshots and repeat the client GET.
For a daemon-free rehearsal run `bash scripts/test-t3code-tailnet.sh` from the
nixfiles root.

## Run or resume a development request

1. Start at each repository's `MEMORY.md`. Inspect the selected host module or
   product entry point, current branch, worktrees and open PRs. Use a clean
   worktree from `origin/main` for a new slice. Resume the existing branch for
   an interrupted one.
2. Name one observable contract and the permitted fixture. Review the worktree's
   `.envrc`, allow it once, and use the loaded shell. In a non-interactive agent
   shell use `direnv exec . <command>` from that worktree. Record the base SHA,
   focused command and failing observation under the repository's ignored
   `artifacts/` directory when available.
3. Apply the smallest repair. Count attempts for each failure in the worktree record or PR description. Record the last observation and next command
   before switching contexts. After three unsuccessful repairs, retain the
   failure and stop that path. Use an independent observable at the normal
   entry point, including a positive control.
4. Review the diff and its side effects, commit and open a PR. In its body
   keep the source SHA, replay commands, mechanism of the failure, independent
   result, untested gates and rollback. Add the durable conclusion to the
   relevant Wiki evidence register. Hosted status is available from the PR.
5. To recover with only the PR, use a clean clone, `gh pr checkout NUMBER --detach`,
   compare `git rev-parse HEAD` with `gh pr view NUMBER --json headRefOid`, then
   replay the first outstanding check. Before publication, use `git worktree list`,
   `git status --short --branch`, the branch log and saved receipts to recover
   uncommitted work and the retry count. Repeat a full verifier only when its
   evidence or source is no longer applicable.

### Executed cycle, 2026-11-18 JST

See the [2026-11-18 T3 Code verification record](t3code-2026-11-18.md).

### Troubleshoot provider probes

If a Codex sign-in or provider probe fails, inspect the local provider status
before modifying authentication state. If `Codex app-server` probes time out
despite valid credentials, official T3 documentation describes
`T3CODE_CODEX_PROBE_TIMEOUT_MS=60000` as a targeted diagnostic setting.

## Rollback

Closing the unmerged PR leaves the running route and service in place. After an
approved installation, reverting the nixfiles commit and activating the reviewed
configuration removes the restore unit. Tailscale owns the route independently.
This cycle observed 8445 **before** any change, so preserve it. If a later
approved restore added a previously absent route, compare the saved snapshot
and obtain approval before removing just its root with
`tailscale serve --https=8445 off`. Leave every other route in place.

To roll back the T3 application, disable `t3code-neko7` and `codex.enable` in
`modules/00-hosts/neko7/configuration.nix`. Obtain approval before you rebuild and activate the prior configuration. Alternatively stop only this unit
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
