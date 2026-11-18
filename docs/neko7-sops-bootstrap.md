# Operator bootstrap: Minecraft secrets on neko7

## Status / deployment boundary

**NOT ENABLED.** `local.features.game-secrets-sops.enable = false` on neko7.
The new code prepares **host-side** `sops-nix` decryption and a
read-only, native NixOS container bind mount of one Tailscale auth key.
The encrypted manifest `secrets/neko7.yaml` and real recipient policy
`.sops.yaml` do **not exist in this PR**; a real age recipient cannot
be inferred from a repository. The user must provision and **commit both
encrypted configuration artifacts** before enabling the host feature.

No NixOS activation/automatic enrollment/credential rotation is performed
by merging this PR.

Current secret:
`sops.secrets."game-minecraft-tailscale-authkey"`
with YAML key `minecraft_tailscale_authkey`. SOPS decrypts
`/run/secrets/game-minecraft-tailscale-authkey` on the **host**.
`containers.neko7-mc.bindMounts` then maps that file read-only to
`/run/host-game-secrets/minecraft-tailscale-authkey` in the guest.
The guest's native `services.tailscale.authKeyFile` uses that path.

## TODO: shortest operator steps (no private key committed)

**Prerequisites:** trusted console or independent Proxmox access, the correct
neko7 SSH **public** host key, local `sops` and `ssh-to-age` tools, a
properly authorized and still-valid Tailscale auth key if one is actually
needed for enrollment, and explicit permission to switch host services.

1. Determine the SSH host public key and convert it to an age recipient:

   ```bash
   ssh neko7 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub' | ssh-to-age
   ```

   Confirm this is the host key used by `sops.age.sshKeyPaths` and that
   the **private** key exists at `/etc/ssh/ssh_host_ed25519_key` on
   neko7. Preserve/back up the existing host private key securely,
   outside Git, **without copying its plaintext into this chat**.

2. In the nixfiles worktree:

   ```bash
   cp .sops.yaml.example .sops.yaml
   $EDITOR .sops.yaml
   mkdir -p secrets
   sops secrets/neko7.yaml
   ```

   Replace the example recipient (and the example regex if the path is
   changed); in the SOPS editor create the YAML key
   `minecraft_tailscale_authkey` and enter its value there. **Never**
   put the token on a command line, into shell history, a Nix string,
   a plaintext Git file, or an issue/PR comment. If the existing node
   is already authenticated and no reusable, valid auth key is
   available, **do not invent or rotate a token**: leave this feature
   disabled until an operator approves credential provisioning.

3. Validate *before* enabling the module. From a machine that has a
   decrypting identity, `sops --decrypt secrets/neko7.yaml >/dev/null`
   must succeed. Check the repository contains only ciphertext and a
   public recipient. Require review of the whole staged diff for
   accidental plaintext and use `git diff --cached --check`.

4. **TODO: required follow-up Git commit.** Change only the host
   selection to `game-secrets-sops.enable = true;`, stage:

   ```bash
   git add .sops.yaml secrets/neko7.yaml modules/00-hosts/neko7/configuration.nix
   git diff --cached --check
   git diff --cached
   git commit -m "feat(neko7): enroll encrypted Minecraft auth secret"
   ```

   The commit may be added to this PR before merging or proposed as a
   separate, operator-approved follow-up. A running node identity is
   **not** proven by successful Nix evaluation.

5. After approving activation from a recovery-capable console:

   ```bash
   nix eval --raw '.#nixosConfigurations.neko7.config.sops.secrets."game-minecraft-tailscale-authkey".path'
   sudo nixos-rebuild test --flake .#neko7
   sudo systemctl status container@neko7-mc.service
   game status minecraft
   game ip minecraft
   ```

   Verify `tailscale status` **inside** the Minecraft container
   still reports its previous node identity, that Minecraft's world is
   unchanged, and that no new node was registered in the tailnet.
   Test secret file ownership and the read-only bind mount without
   printing secret contents. Only then choose to `nixos-rebuild switch`.

## Why this is opt-in, not an automatic source-of-truth migration

- sops-nix writes to `/run/secrets.d/<generation>` and exposes
  `/run/secrets/<name>` as symlinks. A file mounted by systemd-nspawn
  resolves to an inode at container startup and does **not** necessarily
  follow later SOPS generation rotation. The secret declares
  `restartUnits = ["container@neko7-mc.service"]` to remount a new
  generation; this can cause Minecraft downtime. **TODO: authorize any
  real token rotation and restart.** Never rotate silently.
- The Tailscale auth key is a **bootstrap credential**, not the durable
  node identity. Persist `/var/lib/tailscale` in the guest (host bind).
  A key may expire or be one-time-use; a SOPS file cannot make it
  permanently valid. Do not force reauth with the prior node healthy.
- The sops-nix decrypted file and host private key must stay outside
  the Nix Store. Storing the encrypted SOPS manifest in the store is
  acceptable but does not remove the need to protect the host age key.
- If a SOPS host decrypt fails, or if a bind mount/credential is missing,
  **abort** and revert to the prior generation. Do not copy plaintext
  into a persistent `/home/game-*` fallback.
- SOPS may require access to a local operator age identity for future
  edits/rotations. A host-only age recipient can encrypt a new file but
  is inconvenient for repeated operator edits; enroll a separate
  operator recipient only with explicit authorization.
- This PR only provisions the selected Minecraft game. ARK/Rust are
  disabled and their env secrets/Steam identity files remain outside
  this opt-in contract.

## CI versus runtime acceptance

CI can evaluate the default-disabled host and its typed feature flags.
It **cannot** decrypt the operator's not-yet-committed SOPS manifest
or test the live SSH host private key, game session, or Tailscale
identity. Once ciphertext is committed, add a synthetic VM test with
test-only age keys for decryption/mount ordering before turning the
host flag on.

References:
- [sops-nix module and README](https://github.com/Mic92/sops-nix)
- [sops-nix secret generation implementation](https://github.com/Mic92/sops-nix/blob/fe7b4228405aeac2ce7192c2049a6e2bc8637082/pkgs/sops-install-secrets/main.go)
- [NixOS container bind mounts](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/virtualisation/nixos-containers.nix)
- [Tailscale auth keys](https://tailscale.com/docs/features/access-control/auth-keys)
