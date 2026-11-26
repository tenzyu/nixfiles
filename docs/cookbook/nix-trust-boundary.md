# Nix trust boundary (neko5 / neko7)

## Policy

The NixOS `nix` feature sets `nix.settings.accept-flake-config = false`.
This prevents the machine from silently trusting `nixConfig` supplied by
an arbitrary Flake. The repository defines shared substituters and signing keys in
`modules/50-features/nix/nix.nix`. Only the enabled capture or production role adds the SplitCast release
substituter and key from `modules/50-features/media/_internal/cache.nix`.
Do not re-enable global auto-accept to repair a cache miss.

The `nix-access` feature grants the enabled human account
Nix daemon `trusted-users` privileges. This is *not* a sandbox or an
unprivileged build role; granting the feature is a security decision.

The `nix-remote-builder` feature keeps `nixbuilder` trusted because
`ssh-ng` distributed builds use the remote Nix daemon. Its declared
`neko5-nixbuilder.pub` SSH key has OpenSSH `restrict` and a forced
`nix-daemon --stdio` command. That key allows no general SSH shell, PTY or forwarding. **This does not make the Nix daemon RPC itself unprivileged.**
Other pre-existing authorized keys or alternate account access are not
audited merely by this source declaration.

The generic `ssh` feature configures the daemon and Tailnet firewall rule.
It does not configure individual authorized keys. The `neko7-to-neko5` public key is
now declared only by `modules/00-hosts/neko5/configuration.nix`.
This removes that key from the *declarative* neko6/neko7 configuration.
Before switching either host, compare the generated authorized-key files
against active SSH sessions and verify another authorized recovery route.

## Verification before activation

The PR's `Nix validation` job evaluates the effective setting for
neko5/neko7, the restricted authorized key on neko7, and the continued
`ssh-ng` client configuration on neko5. CI evaluation does not test
the running SSH daemon or distributed builds.

After the operator approves the switch, run the relevant checks on each affected host:

```sh
# On neko7: verify the generated key restriction and SSH configuration
sudo grep -F 'nix-daemon --stdio' /etc/ssh/authorized_keys.d/nixbuilder
sudo sshd -T -C user=nixbuilder,host=neko7,addr=127.0.0.1 | grep -i authorizedkeysfile

# On neko5: force an uncached small remote build using the existing ssh-ng
# builder and verify a remote build really occurred (do not merely evaluate).
nix show-config --json | jq '."accept-flake-config".value'
```

The final command checks only the effective configuration. It does not test a remote build. Check the job logs
and negotiated SSH command before claiming continued builder availability.
Do not activate remotely without an access/rollback path.

## Failure and rollback

A remote-builder handshake failure, SSH authorization failure, or loss of
an existing accepted Flake workflow blocks activation. Restore the prior
NixOS generation/SSH key material if needed; no data migration is part
of this change. Use the previous revision of `nix.nix` and
`nix-remote-builder.nix` to revert the policy in Git if the
failure is reproducible.
