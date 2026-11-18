{...}: {
  flake.modules.nixos.game-secrets-sops = {
    config,
    lib,
    ...
  }: {
    # Host-managed encrypted secrets. This is not enabled by default.
    config = lib.mkIf config.local.features.game-secrets-sops.enable {
      # Import of native sops-nix is already supplied by the sops-nix module.
      local.features.sops-nix.enable = lib.mkDefault true;
      assertions = [
        {
          assertion = config.local.features.game-minecraft.enable;
          message = "game-secrets-sops currently provides Minecraft secrets only";
        }
      ];

      # TODO(sops-bootstrap): operator must add secrets/neko7.yaml to Git,
      # encrypted with the verified neko7 SSH-host age recipient.
      # Intentionally missing until provisioning. Do not silently fall back
      # to an unencrypted /home/game-* token.
      sops.defaultSopsFile = ../../../secrets/neko7.yaml;
      sops.secrets."game-minecraft-tailscale-authkey" = {
        key = "minecraft_tailscale_authkey";
        mode = "0400";
        owner = "root";
        # The container bind mounts an actual file inode. When SOPS changes
        # its generation, restart nspawn to remount the newly decrypted inode.
        # TODO(sops-rotation): approve downtime before rotating this token.
        restartUnits = ["container@neko7-mc.service"];
      };
    };
  };
}
