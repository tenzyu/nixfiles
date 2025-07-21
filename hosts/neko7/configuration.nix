{
  inputs,
  pkgs,
  config,
  overlays,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      #
    ];

  nixpkgs.overlays = [
    (import ../../lib/overlays/unstable.nix {inherit inputs;})
  ];

  environment.stub-ld.enable = true;
  programs.nix-ld.enable = true;

  services.tailscale.enable = true;
  networking.resolvconf.extraConfig = ''
    name_server_blacklist=172.16.0.1
  '';
  boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
  boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;

  users.users.tenzyu = {
    extraGroups = ["docker"];
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
