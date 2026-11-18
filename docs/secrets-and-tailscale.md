# Secrets and native Tailscale lifecycle

## Ownership

- NixOS provides `services.tailscale.authKeyFile`, `extraUpFlags`, `extraSetFlags` and the generated `tailscaled-autoconnect` unit. Do not implement another authentication daemon.
- `sops-nix` is an opt-in system feature. Its typed `sops.*` options are available to host declarations and nixd.
- Encrypted secrets belong in a per-host SOPS manifest; **plaintext** values, host private keys and rendered `EnvironmentFile` contents must not enter Git or the Nix store.
- Game container node identities and game save data remain persistent runtime state, not Nix derivation outputs.

## Minecraft example on neko7

Minecraft uses its existing Tailscale identity on neko7. Its auth file is
`/var/lib/game-containers/minecraft/secrets/tailscale-authkey`. The short-lived
enrollment key in the example below would only help if the guest needed
to enroll again. The persistent node identity lives in
`/var/lib/game-containers/minecraft/.state/tailscale` on the host.

If a future service needs this pattern, derive the recipient from the
target host's **public** key with `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`.
Back up the host's decryption identity outside Git. Create a recipient
policy for the encrypted file.

```yaml
creation_rules:
  - path_regex: '^secrets/neko7\.yaml$'
    age: <verified-neko7-age-recipient>
```

Use the SOPS editor to create `secrets/neko7.yaml` with the
`minecraft_tailscale_authkey` field. Verify decryption on the target host
with output suppressed before committing the policy and encrypted YAML.
Select `local.features.sops-nix.enable = true;` in the host's feature
list only when provisioning an actual consumer.

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

A single-file bind holds the inode of the mounted file. SOPS rotates to
a new generation, so the container must restart to pick up a rotated
credential. Schedule the downtime explicitly. After any approved test
activation, verify the guest mount is read-only, compare the Tailscale
node ID, and check Minecraft from neko5 before approving a switch.

## SSH keys

Keep public `authorizedKeys` in host declarations. The private host
key used by `sops.age.sshKeyPaths` must be available before decryption.
The dedicated neko5 remote-builder key
(`/root/.ssh/neko7-nixbuilder`) is a potential runtime secret, but its
recovery would depend on restoring neko5's decryption identity first.
The key accesses neko7's trusted Nix daemon, so an encrypted backup
would need its own recovery plan. See the [Nix trust boundary](nix-trust-boundary.md).

## Validation

- Evaluate `nixosConfigurations.neko7.config.system.build.toplevel.drvPath` and all other existing host derivations.
- Verify `nixosConfigurations.neko7.options.sops.secrets` exists and the feature defaults off.
- Native Tailscale should have exactly one auth ownership path: `services.tailscale.authKeyFile` and the generated `tailscaled-autoconnect`; never the old custom `tailscale-autoconnect`.
- Before any runtime switch, inspect existing node identities, boot activation behavior, network reachability, and secret permissions. Keep an offline rollback and previously working auth files.

Upstream: [sops-nix](https://github.com/Mic92/sops-nix) and [NixOS Tailscale module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/services/networking/tailscale.nix).
