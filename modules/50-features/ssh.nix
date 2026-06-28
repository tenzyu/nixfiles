{lib, ...}: {
  flake.features.ssh.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    services.openssh = {
      enable = lib.mkDefault true;
      settings = {
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
      };
    };
  };
}
