{
  config,
  homeManager,
  nixos,
  ...
}: {
  configurations.nixos.neko7.module = {pkgs, ...}: {
    imports = [
      nixos.nix
      nixos.primaryUser
      nixos.homeManagerUser
      nixos.zsh
      nixos.time
      nixos.ssh
      nixos.locale
      nixos.systemState
      nixos.neko7Hardware
      nixos.unstablePackages
      nixos.stubLd
      nixos.nixLd
      nixos.tailscale
      nixos.resolvconfBlacklistGateway
      nixos.disableIpv6
      nixos.dockerUser
      nixos.docker
      nixos.dockerRootless
      nixos.qemuGuest
      nixos.grubSda
      nixos.kernelLatest
      nixos.networkManager
      nixos.jaExtraLocales
      nixos.usXserverKeyboard
      nixos.fonts
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
