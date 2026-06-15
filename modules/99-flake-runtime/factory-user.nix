{
  lib,
  ...
}: {
  config.flake.lib.userFactory = user: {pkgs, ...}: {
    users.users.${user.name} = {
      isNormalUser = lib.mkDefault true;
      shell =
        if user.shell != null
        then user.shell
        else pkgs.zsh;
      extraGroups =
        (user.extraGroups or [])
        ++ lib.optional user.isAdmin "wheel";
    };

    home-manager.users.${user.name} = {
      programs.home-manager.enable = lib.mkDefault true;
      xdg.enable = lib.mkDefault true;
      home.preferXdgDirectories = lib.mkDefault true;
      home.username = lib.mkDefault user.name;
      home.homeDirectory = lib.mkDefault user.homeDirectory;
      home.stateVersion = lib.mkDefault user.homeStateVersion;
    };
  };
}
