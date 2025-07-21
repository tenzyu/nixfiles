{
  inputs,
  pkgs,
  config,
  overlays,
  lib,
  ...
}: {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      #
    ];

  nixpkgs.overlays = [
    (import ../../lib/overlays/unstable.nix {inherit inputs;})
  ];

  environment.stub-ld.enable = true;

  services.tailscale.enable = true;
  networking.resolvconf.extraConfig = ''
    name_server_blacklist=172.16.0.1
  '';

  users.users.tenzyu = {
    extraGroups = [ "docker" ];
  };
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # Enable QEMU Guest for Proxmox
  services.qemuGuest.enable = true;
}
