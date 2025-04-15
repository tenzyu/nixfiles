{
  lib,
  config,
  pkgs,
  hostname,
  ...
}: username: {
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = ["wheel"]; # Enable sudo for the user
    shell = lib.mkDefault pkgs.zsh;
  };
  home-manager.users.${username} = {
    xdg.enable = true;
    home.preferXdgDirectories = true;

    home.username = username;
    home.homeDirectory = "/home/${username}";
    home.stateVersion = "24.11";

    imports = lib.optional (lib.pathExists ../profiles/${hostname}/configurations.nix) ../profiles/${hostname}/configurations.nix;
  };
}
