{lib, ...}: {
  flake.modules.nixos.ssh = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.ssh.enable {
      services.openssh = {
        enable = lib.mkDefault true;
        openFirewall = false;
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
        };
      };
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
      users.users.tenzyu.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeiSmoim2RKyd6smA5t86Pr7Lt+nOF1oXEHQjsw74O5 neko7-to-neko5"
      ];
    };
  };
}
