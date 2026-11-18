{inputs, ...}: {
  # Make native sops-nix options available through the normal NixOS module
  # graph. Actual encrypted secrets must be defined by their consumers.
  flake.modules.nixos.sops-nix = {
    config,
    lib,
    ...
  }: {
    imports = [inputs.sops-nix.nixosModules.sops];

    config = lib.mkIf config.local.features.sops-nix.enable {
      # An existing, persisted host SSH key is the default age identity.
      # Do not auto-generate or rotate the decryption key during a rebuild.
      sops.age.sshKeyPaths = lib.mkDefault ["/etc/ssh/ssh_host_ed25519_key"];
    };
  };
}
