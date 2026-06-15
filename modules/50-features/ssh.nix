{lib, ...}: {
  flake.modules.nixos.ssh = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.ssh.enable {
      services.openssh = {
        enable = lib.mkDefault true;
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
        };
      };
    };
  };
}
