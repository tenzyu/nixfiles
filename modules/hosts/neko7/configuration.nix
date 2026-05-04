{config, ...}: let
  inherit (config.me) username;
  inherit (config.flake.modules) homeManager nixos;
in {
  configurations.nixos.neko7.module = {pkgs, ...}: {
    imports = [
      nixos.common
      nixos.server
      nixos.neko7Hardware
      {
        networking.hostName = "neko7";

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

          home.packages = with pkgs; [
            jq
            jqp
            playerctl
          ];
        };
      }
    ];
  };
}
