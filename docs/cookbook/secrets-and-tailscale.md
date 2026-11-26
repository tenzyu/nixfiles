# Secrets and native Tailscale lifecycle

## Ownership

- Keep feature selection in the host list and declare each secret in the
  consuming module using native `sops.secrets` and
  `config.sops.secrets.<name>.path`.
- Start with a manifest per host. If recipients, rotation schedules, or maintainers differ, split the files. Give each file only the recipients that need it.
  Keep plaintext values and decryption identities outside Git and the Nix store.
- On neko7, trust extends to root in the guest and to the Proxmox
  administrators who can inspect the VM's memory and storage. SOPS protects
  stored ciphertext. Runtime isolation requires a separate trust boundary.
  User services running as the same UID also share that UID's access.

| Priority | Consumer | Boundary |
| --- | --- | --- |
| High | neko7 service passwords, API keys, and provisioned TLS keys | Use a native file option or `LoadCredential`. Keep automatically renewed certificates in the certificate manager's runtime state. |
| High | SplitCast and Twitch | The pinned SplitCast accepts a stream key through `obs.twitch_key_file` and checks its ownership, mode, and size. Use a service-owned private file when the candidate is approved. Treat OAuth access tokens and rotating refresh tokens as application-owned state. Keep automatic restarts off during a broadcast. |
| High | OpenCode and T3 Code | OpenCode provider configuration supports `{file:/path/to/key}`. Verify the selected provider and pinned version before wiring a real key. The running OpenCode unit is manually managed and uses an environment file for its server password. T3 Code uses the existing Codex CLI login. Scope any new external API key to its actual provider process. |
| Medium | Game guest enrollment | A new Tailscale auth key can be provided as a read-only bind mount. Preserve the guest's existing node state. |
| Medium | neko5 user applications | Use Home Manager's native sops-nix module when a specific user application needs it. Keep user credentials in that user's runtime scope. |
| As needed | NixOS user password hashes | Set `neededForUsers = true` and use the runtime path in `hashedPasswordFile`. |
| Out of scope | Public configuration, public SSH keys, and persistent application state | Keep public configuration in its normal modules. Back up mutable state through the owning service. |

The current host declarations select only the decryption identity. Each
application still needs its own credential declaration and acceptance.

The SplitCast Rust candidate stays gated. Its file input above carries an
OBS stream key. OAuth refresh belongs in the OAuth client, which must save
the latest refresh token when Twitch returns a replacement.
[Twitch token refresh](https://dev.twitch.tv/docs/authentication/refresh-tokens/)
· [OpenCode config variables](https://opencode.ai/docs/config/#variables)

## Provision and recover a host age identity

The neko5 and neko7 feature declarations select the same local path,
`/var/lib/sops-nix/key.txt`, with a **different** age identity on each
machine. The parent directory is root-owned with mode `0700` and the key
file is root-owned with mode `0600`. Store a verified copy of each
identity in a separate Bitwarden Secure Note for recovery. Routine
activation reads the local key and works offline. Rebuilds do not
auto-generate a replacement identity.

If a host has no identity, create the directory.
As root with a restrictive umask, run `age-keygen -o /var/lib/sops-nix/key.txt`.
Record only the recipient printed by
`age-keygen -y /var/lib/sops-nix/key.txt` in the SOPS policy. Confirm a
Bitwarden restore derives the same public recipient and decrypts a
fixture before depending on the backup. Back up the encrypted manifests
as well. A replacement host can restore the saved age identity before
activating any service that needs it.

For an intentional age key replacement, keep a verified recovery identity
and both the old and new keys until acceptance. Update the recipient policy.
Run `sops updatekeys` for the affected files.
Before retiring the old identity, verify decryption with the new identity. If a recipient was
compromised, review historical ciphertext, rotate affected SOPS data
keys, and rotate or revoke exposed service credentials at the provider.
Changing recipients cannot revoke a token or remove old Git history.
The dedicated age keys on neko5 and neko7 make SSH host-key rotation
independent of SOPS. Deployments that use SSH-derived recipients must
reencrypt for the next host key before removing the old one.

## Deliver credentials to services

1. Use the service's native `passwordFile`, `tokenFile`, or `authKeyFile`
   with the SOPS runtime path when supported.
2. For a systemd unit that accepts a credential path, use
   `LoadCredential` with the secret's evaluated runtime path:

   ```nix
   {config, ...}: {
   	systemd.services.example.serviceConfig.LoadCredential = [
   		"api-key:${config.sops.secrets.example-api-key.path}"
   	];
   }
   ```

   Point the consumer at `$CREDENTIALS_DIRECTORY/api-key` or pass a file
   path using the `%d` specifier in the unit.
3. For applications that require an inline value in a config file, use
   `sops.templates` with placeholders and restrict the rendered file's
   owner and mode. Choose a format or encoding that the consumer parses
   safely.
4. Use an `EnvironmentFile` only for applications that require environment variables.
   Account for inheritance by child processes and diagnostic output.
   [systemd.exec credential and environment options](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#Credentials)

Audit the receiving process too. Both ARK implementations embed
`ARK_ADMIN_PASSWORD` in the server URL passed in argv. Moving those
environment files into SOPS would leave the argv and logging exposure.
Resolve that consumption path before migrating the credential.

SOPS changes take effect on the NixOS activation path. If the application can reopen and reload the secret, use `reloadUnits`.
If the application reads the secret at startup or systemd must refresh its credential snapshot, use `restartUnits`. Schedule interruptions explicitly. Keep
provider token expiry, refresh, and revocation with the credential's
owner.

## Minecraft example on neko7

Minecraft uses its existing Tailscale identity on neko7. Its auth file is
`/var/lib/game-containers/minecraft/secrets/tailscale-authkey`. The short-lived
enrollment key in the example below would only help if the guest needed
to enroll again. The persistent node identity lives in
`/var/lib/game-containers/minecraft/.state/tailscale` on the host.

If a future service needs this pattern, use the recipient from the
target host's provisioned age identity. Create a recipient policy for
the encrypted file.

```yaml
creation_rules:
  - path_regex: '^secrets/neko7\.yaml$'
    age: <verified-neko7-age-recipient>
```

Use the SOPS editor to create `secrets/neko7.yaml` with the
`minecraft_tailscale_authkey` field. Verify decryption on the target host
with output suppressed before committing the policy and encrypted YAML.
On a new host, select `local.features.sops-nix.enable = true;` after
provisioning its local age identity.

The example assumes the module is beside `secrets/`. In the module that
owns the guest, replace both existing auth path definitions together.

```nix
{
	config,
	lib,
	...
}: let
	secretName = "game-minecraft-tailscale-authkey";
	guestPath = "/run/host-game-secrets/minecraft-tailscale-authkey";
in {
	sops.secrets.${secretName} = {
		sopsFile = ./secrets/neko7.yaml;
		key = "minecraft_tailscale_authkey";
		owner = "root";
		mode = "0400";
		restartUnits = ["container@neko7-mc.service"];
	};

	containers.neko7-mc = {
		bindMounts.${guestPath} = {
			hostPath = config.sops.secrets.${secretName}.path;
			isReadOnly = true;
		};
		config = {
			services.tailscale.authKeyFile = guestPath;
			systemd.services.tailscaled-autoconnect.unitConfig.ConditionPathExists = guestPath;
		};
	};

	systemd.services."container@neko7-mc" = lib.mkIf config.sops.useSystemdActivation {
		after = ["sops-install-secrets.service"];
		requires = ["sops-install-secrets.service"];
	};
}
```

A single-file bind mount holds the inode of the mounted file. SOPS rotates the secret to a new generation. Restart the container to use the rotated credential. Schedule the downtime explicitly. After any approved test
activation, verify the guest mount is read-only, compare the Tailscale
node ID, and check Minecraft from neko5 before approving a switch.

## SSH keys

Keep public `authorizedKeys` in host declarations. The dedicated neko5
remote-builder key (`/root/.ssh/neko7-nixbuilder`) is a potential runtime
secret. Confirm local key recovery and a remote build before changing
that credential. It accesses neko7's trusted Nix daemon. See the
[Nix trust boundary](nix-trust-boundary.md).

## Validation

- Evaluate `nixosConfigurations.neko7.config.system.build.toplevel.drvPath` and all other existing host derivations.
- Verify neko5 and neko7 resolve the local key file and do not import
  either SSH host key. Try a synthetic ciphertext for each recipient
  on both hosts. Only its intended host should decrypt it.
- Native Tailscale must have exactly one auth ownership path through `services.tailscale.authKeyFile` and the generated `tailscaled-autoconnect`. Do not use the old custom `tailscale-autoconnect`.
- Before any runtime switch, inspect existing node identities, boot activation behavior, network reachability, and secret permissions. Keep an offline rollback and previously working auth files.

Upstream documentation includes [sops-nix](https://github.com/Mic92/sops-nix) and [NixOS Tailscale module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/services/networking/tailscale.nix).
