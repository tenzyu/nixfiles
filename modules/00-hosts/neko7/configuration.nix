{
  cross,
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
      nixos.docker
      nixos.qemuGuest
      nixos.grubSda
      nixos.kernelLatest
      nixos.networkManager
      nixos.jaExtraLocales
      nixos.usXserverKeyboard
      nixos.fonts
      (cross.user "tenzyu" (
        (with cross.modules; [
          catppuccin
        ])
        ++ (with homeManager; [
          common
          packagesCommon
          zsh
          btop
          fastfetch
          fzf
          git
          kitty
          neovim
          rofi
          starship
          tmux
          waybar
          mako
          wlogout
          yazi
          zoxide
        ])
      ))
      ({pkgs, ...}: {
        home-manager.users."tenzyu".home.packages = with pkgs; [
          nh
          jq
          jqp
          lazygit
          zip
          ncdu
          crosspipe
        ];
      })
    ];
  };
}
