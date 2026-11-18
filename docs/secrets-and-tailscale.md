# Secrets and native Tailscale lifecycle

## Ownership

- NixOS provides `services.tailscale.authKeyFile`, `extraUpFlags`, `extraSetFlags` and the generated `tailscaled-autoconnect` unit. Do not implement another authentication daemon.
- `sops-nix` is an opt-in system feature; no keys, encrypted payloads or existing credentials are created by this PR. The module is imported so its typed `sops.*` options are available to host declarations and nixd.
- Encrypted secrets belong in a per-host SOPS manifest; **plaintext** values, host private keys and rendered `EnvironmentFile` contents must not enter Git or the Nix store.
- Game container node identities and game save data remain persistent runtime state, not Nix derivation outputs.

## Future activation (requires provisioning and operator approval)

Enable `local.features.sops-nix.enable = true;` on a host *only after* its SSH host key has been backed up and its age recipient has been enrolled. Define each secret under `sops.secrets` in the relevant NixOS module, for example:

```nix
sops.defaultSopsFile = ./secrets/neko7.yaml; # encrypted file
sops.secrets."ark-tailscale" = {
  owner = "root";
  mode = "0400";
};
```

Use `config.sops.secrets."ark-tailscale".path` as a runtime file path. For a **container**, provide a read-only bind mount from the host's decrypted secret to the path consumed by its `services.tailscale.authKeyFile`, with an ordering dependency ensuring the secret exists before authentication. A missing key must not trigger implicit re-registration. Do not copy a plaintext token into `environment.variables`, `pkgs.writeText`, or `builtins.toFile`.

The existing paths `/home/game-*/secrets/tailscale-authkey` remain the active paths in this PR. Moving them to sops-nix is a **separate, data-bearing migration**: obtain the actual recipient keys, encrypt each secret, preserve old Tailscale identity state and validate access before removing the old file. Do not commit example tokens and do not apply to production automatically.

## Validation

- Evaluate `nixosConfigurations.neko7.config.system.build.toplevel.drvPath` and all other existing host derivations.
- Verify `nixosConfigurations.neko7.options.sops.secrets` exists and the feature defaults off.
- Native Tailscale should have exactly one auth ownership path: `services.tailscale.authKeyFile` and the generated `tailscaled-autoconnect`; never the old custom `tailscale-autoconnect`.
- Before any runtime switch, inspect existing node identities, boot activation behavior, network reachability, and secret permissions. Keep an offline rollback and previously working auth files.

Upstream: [sops-nix](https://github.com/Mic92/sops-nix) and [NixOS Tailscale module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/services/networking/tailscale.nix).
