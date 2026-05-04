{
  config,
  homeManager,
  nixos,
  ...
}: {
  configurations.nixos.neko6.module = {pkgs, ...}: {
    imports = [
      nixos.nix
      nixos.primaryUser
      nixos.homeManagerUser
      nixos.zsh
      nixos.time
      nixos.ssh
      nixos.locale
      nixos.systemState
      nixos.unstablePackages
      nixos.wslIntegration
      nixos.passwordlessSudo
      nixos.sshDebug
      nixos.dockerUser
      nixos.nixLd
      nixos.docker
      nixos.dockerOnBoot
      nixos.dockerAutoPrune
      nixos.emptyNixAccessTokens
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
          home.packages = with pkgs; [devbox];
          home.sessionVariables.NIXOS_OZONE_WL = "1";
        };
      }
    ];
  };
}
