{
  config,
  lib,
  ...
}: {
  flake.modules.nixos.homeManagerUser = {
    home-manager.users.${config.me.username} = {
      programs.home-manager.enable = lib.mkDefault true;
      xdg.enable = lib.mkDefault true;
      home.preferXdgDirectories = lib.mkDefault true;
      home.username = lib.mkDefault config.me.username;
      home.homeDirectory = lib.mkDefault "/home/${config.me.username}";
      home.stateVersion = config.me.stateVersion;
    };
  };
}
