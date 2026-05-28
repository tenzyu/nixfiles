{
  config,
  lib,
  ...
}: let
  inherit (config.me) stateVersion username;
in {
  flake.modules.nixos.homeManagerUser = {config, ...}: {
    home-manager.users.${username} = {
      programs.home-manager.enable = lib.mkDefault true;
      xdg.enable = lib.mkDefault true;
      home.preferXdgDirectories = lib.mkDefault true;
      home.username = lib.mkDefault username;
      home.homeDirectory = lib.mkDefault "/home/${username}";
      home.stateVersion = stateVersion;
    };

    # Keep this convenience link moving with Home Manager's active generation.
    systemd.tmpfiles.rules = [
      "L+ /tmp/${config.networking.hostName}-home-files - - - - /home/${username}/.local/state/home-manager/gcroots/current-home/home-files"
    ];
  };
}
