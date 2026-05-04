{lib, ...}: {
  flake.modules.nixos.networkManager = {
    networking.networkmanager.enable = lib.mkDefault true;
  };
}
