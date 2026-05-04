{
  config,
  homeManager,
  nixos,
  ...
}: {
  configurations.nixos.neko7.module = {pkgs, ...}: {
    imports = [
      nixos.common
      nixos.server
      nixos.neko7Hardware
      {
        home-manager.users.${config.me.username} = {
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
