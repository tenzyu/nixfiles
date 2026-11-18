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
      # Provision a distinct, backed-up identity on each host before adding secrets.
      sops.age.keyFile = lib.mkDefault "/var/lib/sops-nix/key.txt";
      sops.age.sshKeyPaths = lib.mkDefault [];
      sops.gnupg.sshKeyPaths = lib.mkDefault [];
    };
  };
}
