{config, ...}: let
  inherit (config.me) username;
  inherit (config.flake.modules) homeManager nixos;
in {
  configurations.nixos.neko6.module = {pkgs, ...}: {
    imports = [
      nixos.common
      nixos.wsl
      {
        home-manager.users.${username} = {
          imports = [
            homeManager.common
            homeManager.packagesCommon
            homeManager.zsh
            homeManager.btop
            homeManager.fastfetch
            homeManager.fzf
            homeManager.git
            homeManager.neovim
            homeManager.tmux
            homeManager.yazi
          ];
          home.packages = with pkgs; [devbox];
          home.sessionVariables.NIXOS_OZONE_WL = "1";
        };
      }
    ];
  };
}
