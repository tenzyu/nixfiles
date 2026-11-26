# Verify Minecraft backups

`nix build -L --no-link .#checks.x86_64-linux.game-backup-minecraft` runs the
packaged operator and writer with inert lifecycle and privilege-transition
mocks. It injects I/O faults and restores the archive into an isolated
directory. The same packaged fixture can use the real `setpriv` by
building `(import ./test.nix { inherit pkgs; root = fixturePath;
mockIdentity = false; }).runner` and running it in a private user and
mount namespace with UID/GID 0 and 27009 mapped and a fresh tmpfs at
`fixturePath`. It still uses inert managers.

Real host acceptance is **NOT RUN**. Obtain separate approval for a dated test of the native `sudo` wrapper, tmpfiles inode, installed guest manager's clean-stop properties, destination's local persistent filesystem, and absence of bypass writers. An unexpected unit state
or missing privilege or filesystem capability is a refusal. The fixtures
establish descriptor retention and syscall ordering, with no power-loss
claim.

See the [backup and recovery procedure](README.md).
