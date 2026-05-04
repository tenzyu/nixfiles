{config, ...}: let
  inherit (config.flake.modules) homeManager nixos;
  inherit (config.flake.lib.cross) user;
  cross = config.flake.lib.cross.modules;
in {
  configurations.nixos.neko5.module = {
    imports = [
      nixos.kernelLatest
      nixos.common
      nixos.desktop
      nixos.neko5Hardware
      (user "tenzyu" [
        cross.obsidian
        cross.parsec
        cross.discord
        cross.prismlauncher
        cross.codex
        cross.gemini-cli
        cross.antigravity
        cross.osu-lazer
        cross.catppuccin
        cross.hyprland
        homeManager.common
        homeManager.packagesCommon
        homeManager.packagesDesktop
        homeManager.zsh
        homeManager.btop
        homeManager.fastfetch
        homeManager.firefox
        homeManager.fzf
        homeManager.git
        homeManager.hyprpaper
        homeManager.kitty
        homeManager.neovim
        homeManager.rofi
        homeManager.starship
        homeManager.tmux
        homeManager.waybar
        homeManager.wlogout
        homeManager.yazi
        homeManager.zedEditor
        homeManager.zoxide
      ])
      ({pkgs, ...}: {
        home-manager.users."tenzyu".home.packages = with pkgs; [
          nh
          jq
          jqp
          lazygit
          zip
          unstable.anki-bin
          unstable.gh
        ];
      })
    ];
  };
}
